use starknet::ContractAddress;

#[derive(Drop, Serde, starknet::Store)]
pub struct Market {
    name: ByteArray,
    outcomes: (Outcome, Outcome),
    category: felt252,
    isSettled: bool,
    isActive: bool,
    betToken: ContractAddress,
    winningOutcome: Option<Outcome>,
    moneyInPool: u256,
}

#[derive(Drop, Copy, Serde, starknet::Store, PartialEq, Eq, Hash)]
pub struct Outcome {
    name: felt252,
    currentOdds: u256,
    boughtShares: u256,
}

#[starknet::interface]
pub trait IMarketFactory<TContractState> {
    fn createMarket(
        ref self: TContractState,
        name: ByteArray,
        outcomes: (felt252, felt252),
        betToken: ContractAddress,
        category: felt252
    );

    fn getMarketCount(self: @TContractState) -> u256;

    fn buyShares(ref self: TContractState, marketId: u256, tokenToMint: u8, amount: u256) -> bool;

    fn settleMarket(ref self: TContractState, marketId: u256, winningOutcome: Outcome);

    fn toggleMarketStatus(ref self: TContractState, marketId: u256);

    fn claimWinnings(ref self: TContractState, marketId: u256, receiver: ContractAddress);

    fn getMarket(self: @TContractState, marketId: u256) -> Market;

    fn getAllMarkets(self: @TContractState) -> Array<Market>;

    fn getMarketByCategory(self: @TContractState, category: felt252) -> Array<Market>;

    fn getContractOwner(self: @TContractState) -> ContractAddress;

    fn calcProbabilty(ref self: TContractState, marketId: u256, outcome: Outcome) -> u256;

    fn withdrawFromTreasury(ref self: TContractState, token: ContractAddress) -> bool;
// functions to define if we implement pools for the betting platform.

// fn createTokenPool(ref self: TContractState, tokenAddress: ContractAddress, initialLiquidity: u256) ->  ContractAddress;

// fn addLiquidity(ref self: TContractState, poolAddress: ContractAddress, amount: u256) -> bool;

// fn removeLiquidity(ref self: TContractState, poolAddress: ContractAddress, amount: u256) -> bool;
}

pub trait IMarketFactoryImpl<TContractState> {
    fn calcOdds(ref self: TContractState, marketId: u256) -> Array<u256>;

    // fn marginAdjustedOdds(
    //     ref self: TContractState, marketId: u256, probabilities: @Array<u256>, margin: u256
    // ) -> Array<u256>;

    fn isMarketResolved(self: @TContractState, marketId: u256) -> bool;
}

#[starknet::contract]
pub mod MarketFactory {
    use raize_contracts::MarketFactory::IMarketFactoryImpl;
    use openzeppelin::token::erc20::interface::IERC20DispatcherTrait;
    use core::box::BoxTrait;
    use core::option::OptionTrait;
    use core::array::ArrayTrait;
    use super::{Market, Outcome};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use core::num::traits::zero::Zero;
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;

    const one: u256 = 1_000_000_000_000_000_000;
    const MAX_ITERATIONS: u16 = 25;
    const PLATFORM_FEE: u256 = 50;
    #[storage]
    struct Storage {
        userBet: LegacyMap::<(ContractAddress, u256), Outcome>,
        // markets: Array<Market>
        markets: LegacyMap::<u256, Market>,
        idx: u256,
        treasury: LegacyMap::<ContractAddress, u256>, // for the contract to hold the money
        userPortfolio: LegacyMap::<
            (ContractAddress, Outcome), u256
        >, // read outcome with market id and user name, then read portfolio using contract address and outcome.
        owner: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.owner.write(get_caller_address());
    }


    fn createShareTokens(names: (felt252, felt252)) -> (Outcome, Outcome) {
        let (name1, name2) = names;
        let mut token1 = Outcome { name: name1, boughtShares: 0, currentOdds: 2 * one };
        let mut token2 = Outcome { name: name2, boughtShares: 0, currentOdds: 2 * one };

        let tokens = (token1, token2);

        return tokens;
    }

    #[abi(embed_v0)]
    impl MarketFactory of super::IMarketFactory<ContractState> {
        fn createMarket(
            ref self: ContractState,
            name: ByteArray,
            outcomes: (felt252, felt252),
            betToken: ContractAddress,
            category: felt252
        ) {
            // the entire money stays in the contract, treasury keeps count of how much the platform is making as revenue, the rest amount in the market 
            let outcomes = createShareTokens(outcomes);
            let market = Market {
                name,
                outcomes,
                isSettled: false,
                isActive: true,
                winningOutcome: Option::None,
                betToken: betToken,
                moneyInPool: 0,
                category,
            };
            self.idx.write(self.idx.read() + 1); // 0 -> 1
            self.markets.write(self.idx.read(), market); // write market to storage
        }
        fn getMarket(self: @ContractState, marketId: u256) -> Market {
            return self.markets.read(marketId);
        }

        fn getMarketCount(self: @ContractState) -> u256 {
            return self.idx.read();
        }

        fn toggleMarketStatus(ref self: ContractState, marketId: u256) {
            let mut market = self.markets.read(marketId);
            market.isActive = !market.isActive;
            self.markets.write(marketId, market);
        }

        // creates a position in a market for a user
        fn buyShares(
            ref self: ContractState, marketId: u256, tokenToMint: u8, amount: u256
        ) -> bool {
            let mut market = self.markets.read(marketId);
            let token = self.userBet.read((get_caller_address(), marketId));
            let (outcome1, outcome2) = market.outcomes;
            assert(token.boughtShares.is_zero(), '');
            let dispatcher = IERC20Dispatcher { contract_address: market.betToken };
            if tokenToMint == 0 {
                let mut outcome = outcome1;
                let _approval = dispatcher.approve(get_contract_address(), amount);
                let txn: bool = dispatcher
                    .transfer_from(get_caller_address(), get_contract_address(), amount);
                let treasuryBalance = self.treasury.read(market.betToken);
                self.treasury.write(market.betToken, treasuryBalance + amount * PLATFORM_FEE / 100);
                outcome.boughtShares = outcome.boughtShares + amount;
                let updatedOdds = self.calcOdds(marketId);
                let mut otherOutcome = outcome2;
                outcome.currentOdds = *updatedOdds.at(0);
                otherOutcome.currentOdds = *updatedOdds.at(1);
                self.userBet.write((get_caller_address(), marketId), outcome);
                self.userPortfolio.write((get_caller_address(), outcome), amount);
                txn
            } else {
                let mut outcome = outcome2;
                let _approval = dispatcher.approve(get_contract_address(), amount);
                let txn: bool = dispatcher
                    .transfer_from(get_caller_address(), get_contract_address(), amount);
                outcome.boughtShares = outcome.boughtShares + amount;
                let updatedOdds = self.calcOdds(marketId);
                let mut otherOutcome = outcome1;
                outcome.currentOdds = *updatedOdds.at(1);
                otherOutcome.currentOdds = *updatedOdds.at(0);
                self.userBet.write((get_caller_address(), marketId), outcome);
                self.userPortfolio.write((get_caller_address(), outcome), amount);
                txn
            }
        }

        fn claimWinnings(ref self: ContractState, marketId: u256, receiver: ContractAddress) {
            assert!(marketId <= self.idx.read(), "Market does not exist");
            let market = self.markets.read(marketId);
            assert!(market.isSettled == true, "Market isn't settled.");
            let userOutcome: Outcome = self.userBet.read((receiver, marketId));
            let betAmount: u256 = self.userPortfolio.read((receiver, userOutcome));
            let mut winnings = 0;
            let winningOutcome = market.winningOutcome.unwrap();
            assert!(userOutcome == winningOutcome, "User didn't win!");
            winnings = betAmount * market.moneyInPool / userOutcome.boughtShares;
            let dispatcher = IERC20Dispatcher { contract_address: market.betToken };
            dispatcher.transfer(receiver, winnings);
            self.userPortfolio.write((receiver, userOutcome), 0);
        }

        fn settleMarket(ref self: ContractState, marketId: u256, winningOutcome: Outcome) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can settle markets.');
            let mut market = self.markets.read(marketId);
            market.isSettled = true;
            market.winningOutcome = Option::Some(winningOutcome);
            self.markets.write(marketId, market);
        }

        fn getAllMarkets(self: @ContractState) -> Array<Market> {
            let mut markets: Array<Market> = ArrayTrait::new();
            let mut i: u256 = 0;
            loop {
                if i == self.idx.read() {
                    break;
                }
                markets.append(self.markets.read(i));
                i += 1;
            };
            markets
        }

        fn getContractOwner(self: @ContractState) -> ContractAddress {
            return self.owner.read();
        }

        fn getMarketByCategory(self: @ContractState, category: felt252) -> Array<Market> {
            let mut markets: Array<Market> = ArrayTrait::new();
            let mut i: u256 = 0;
            loop {
                if i == self.idx.read() {
                    break;
                }
                let market = self.markets.read(i);
                if market.category == category {
                    markets.append(market);
                }
                i += 1;
            };
            markets
        }

        fn calcProbabilty(ref self: ContractState, marketId: u256, outcome: Outcome) -> u256 {
            let market = self.markets.read(marketId);
            let (outcome1, outcome2) = market.outcomes;
            let totalShares = outcome1.boughtShares + outcome2.boughtShares;
            let outcomeShares = outcome.boughtShares;
            return outcomeShares / totalShares;
        }

        fn withdrawFromTreasury(ref self: ContractState, token: ContractAddress) -> bool {
            let treasuryBalance = self.treasury.read(token);
            let dispatcher = IERC20Dispatcher { contract_address: token };
            let tx = dispatcher.transfer(self.owner.read(), treasuryBalance);
            tx
        }
    }

    impl MarketFactoryImpl of super::IMarketFactoryImpl<ContractState> {
        fn isMarketResolved(self: @ContractState, marketId: u256) -> bool {
            let market = self.markets.read(marketId);
            return market.isSettled;
        }

        fn calcOdds(ref self: ContractState, marketId: u256) -> Array<u256> {
            let market = self.markets.read(marketId);
            let (outcome1, outcome2) = market.outcomes;
            let mut odds: Array<u256> = ArrayTrait::new();
            let oddOutcome1 = (outcome1.boughtShares + outcome2.boughtShares)
                / outcome1.boughtShares;
            let oddOutcome2 = (outcome1.boughtShares + outcome2.boughtShares)
                / outcome2.boughtShares;
            odds.append(oddOutcome1);
            odds.append(oddOutcome2);
            odds
        // }
        }
    }
}
