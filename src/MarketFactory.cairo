use starknet::ContractAddress;

#[derive(Drop, Serde, starknet::Store)]
pub struct Market {
    name: ByteArray,
    description: ByteArray,
    outcomes: (Outcome, Outcome),
    category: felt252,
    image: ByteArray,
    isSettled: bool,
    isActive: bool,
    deadline: felt252,
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

#[derive(Drop, Serde, starknet::Store)]
pub struct UserPosition {
    amount: u256,
    hasClaimed: bool,
}

#[starknet::interface]
pub trait IMarketFactory<TContractState> {
    fn createMarket(
        ref self: TContractState,
        name: ByteArray,
        description: ByteArray,
        outcomes: (felt252, felt252),
        betToken: ContractAddress,
        category: felt252,
        image: ByteArray,
        deadline: felt252,
    );

    fn getMarketCount(self: @TContractState) -> u256;

    fn buyShares(ref self: TContractState, marketId: u256, tokenToMint: u8, amount: u256) -> bool;

    fn settleMarket(ref self: TContractState, marketId: u256, winningOutcome: u8);

    fn toggleMarketStatus(ref self: TContractState, marketId: u256);

    fn claimWinnings(ref self: TContractState, marketId: u256, receiver: ContractAddress);

    fn getMarket(self: @TContractState, marketId: u256) -> Market;

    fn getAllMarkets(self: @TContractState) -> Array<Market>;

    fn getMarketByCategory(self: @TContractState, category: felt252) -> Array<Market>;

    fn getContractOwner(self: @TContractState) -> ContractAddress;

    fn calcProbabilty(self: @TContractState, marketId: u256, outcome: Outcome) -> u256;

    fn getUserMarkets(self: @TContractState, user: ContractAddress) -> Array<Market>;

    fn checkForApproval(self: @TContractState, token: ContractAddress, amount: u256) -> bool;

    fn getOwner(self: @TContractState) -> ContractAddress;

    fn getTreasuryWallet(self: @TContractState) -> ContractAddress;

    fn setTreasuryWallet(ref self: TContractState, wallet: ContractAddress);
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
    use super::{Market, Outcome, UserPosition};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use core::num::traits::zero::Zero;
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;

    const one: u256 = 1_000_000_000_000_000_000;
    const MAX_ITERATIONS: u16 = 25;
    const PLATFORM_FEE: u256 = 2;
    #[storage]
    struct Storage {
        userBet: LegacyMap::<(ContractAddress, u256), Outcome>,
        // markets: Array<Market>
        markets: LegacyMap::<u256, Market>,
        idx: u256,
        userPortfolio: LegacyMap::<
            (ContractAddress, Outcome), UserPosition
        >, // read outcome with market id and user name, then read portfolio using contract address and outcome.
        owner: ContractAddress,
        treasuryWallet: ContractAddress,
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MarketCreated: MarketCreated,
        ShareBought: ShareBought,
        MarketSettled: MarketSettled,
        MarketToggled: MarketToggled,
        WinningsClaimed: WinningsClaimed,
        WithdrawnFromTreasury: WithdrawnFromTreasury,
    }
    #[derive(Drop, starknet::Event)]
    struct MarketCreated {
        market: Market
    }
    #[derive(Drop, starknet::Event)]
    struct ShareBought {
        user: ContractAddress,
        market: Market,
        outcome: Outcome,
        amount: u256
    }
    #[derive(Drop, starknet::Event)]
    struct MarketSettled {
        market: Market
    }
    #[derive(Drop, starknet::Event)]
    struct MarketToggled {
        market: Market
    }
    #[derive(Drop, starknet::Event)]
    struct WinningsClaimed {
        user: ContractAddress,
        market: Market,
        outcome: Outcome,
        amount: u256
    }
    #[derive(Drop, starknet::Event)]
    struct WithdrawnFromTreasury {
        token: ContractAddress,
        amount: u256
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.owner.write(get_caller_address());
    }


    fn createShareTokens(names: (felt252, felt252)) -> (Outcome, Outcome) {
        let (name1, name2) = names;
        let mut token1 = Outcome { name: name1, boughtShares: one, currentOdds: 2 * one };
        let mut token2 = Outcome { name: name2, boughtShares: one, currentOdds: 2 * one };

        let tokens = (token1, token2);

        return tokens;
    }

    #[abi(embed_v0)]
    impl MarketFactory of super::IMarketFactory<ContractState> {
        fn createMarket(
            ref self: ContractState,
            name: ByteArray,
            description: ByteArray,
            outcomes: (felt252, felt252),
            betToken: ContractAddress,
            category: felt252,
            image: ByteArray,
            deadline: felt252,
        ) {
            // the entire money stays in the contract, treasury keeps count of how much the platform is making as revenue, the rest amount in the market 
            let outcomes = createShareTokens(outcomes);
            let market = Market {
                name,
                description,
                outcomes,
                isSettled: false,
                isActive: true,
                winningOutcome: Option::None,
                betToken: betToken,
                moneyInPool: 0,
                category,
                image,
                deadline
            };
            self.idx.write(self.idx.read() + 1); // 0 -> 1
            self.markets.write(self.idx.read(), market); // write market to storage
            let currentMarket = self.markets.read(self.idx.read());
            self.emit(MarketCreated { market: currentMarket });
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
            let currentMarket = self.markets.read(marketId);
            self.emit(MarketToggled { market: currentMarket });
        }

        fn checkForApproval(self: @ContractState, token: ContractAddress, amount: u256) -> bool {
            let dispatcher = IERC20Dispatcher { contract_address: token };
            let approval = dispatcher.allowance(get_caller_address(), get_contract_address());
            return approval >= amount;
        }

        fn getUserMarkets(self: @ContractState, user: ContractAddress) -> Array<Market> {
            let mut markets: Array<Market> = ArrayTrait::new();
            let mut i: u256 = 0;
            loop {
                if i == self.idx.read() {
                    break;
                }
                let market = self.markets.read(i);
                let userOutcome = self.userBet.read((user, i));
                if userOutcome.currentOdds != 0 {
                    markets.append(market);
                }
                i += 1;
            };
            markets
        }

        // creates a position in a market for a user
        fn buyShares(
            ref self: ContractState, marketId: u256, tokenToMint: u8, amount: u256
        ) -> bool {
            let market = self.markets.read(marketId);
            assert!(market.isActive == true, "Market is not active.");
            let token = self.userBet.read((get_caller_address(), marketId));
            let (outcome1, outcome2) = market.outcomes;
            assert(token.boughtShares.is_zero(), '');
            let dispatcher = IERC20Dispatcher { contract_address: market.betToken };
            if tokenToMint == 0 {
                let mut outcome = outcome1;
                // let _approval = dispatcher.approve(get_contract_address(), amount);
                let txn: bool = dispatcher
                    .transfer_from(get_caller_address(), get_contract_address(), amount);
                dispatcher
                    .transfer_from(
                        get_contract_address(),
                        self.treasuryWallet.read(),
                        amount * PLATFORM_FEE * one / 100
                    );
                outcome.boughtShares = outcome.boughtShares
                    + (amount * one - amount * one * PLATFORM_FEE / 100);
                let marketClone = self.markets.read(marketId);
                let moneyInPool = marketClone.moneyInPool
                    + amount * one
                    - amount * PLATFORM_FEE * one / 100;
                let newMarket = Market {
                    outcomes: (outcome, outcome2), moneyInPool: moneyInPool, ..marketClone
                };
                self.markets.write(marketId, newMarket);
                let updatedOdds = self.calcOdds(marketId);
                let mut otherOutcome = outcome2;
                outcome.currentOdds = *updatedOdds.at(0);
                otherOutcome.currentOdds = *updatedOdds.at(1);
                let marketClone = self.markets.read(marketId);
                let oddsUpdatedMarket = Market { outcomes: (outcome, otherOutcome), ..marketClone };
                self.markets.write(marketId, oddsUpdatedMarket);
                self.userBet.write((get_caller_address(), marketId), outcome);
                self
                    .userPortfolio
                    .write(
                        (get_caller_address(), outcome),
                        UserPosition { amount: amount, hasClaimed: false }
                    );
                let updatedMarket = self.markets.read(marketId);
                self
                    .emit(
                        ShareBought {
                            user: get_caller_address(),
                            market: updatedMarket,
                            outcome: outcome,
                            amount: amount
                        }
                    );
                txn
            } else {
                let mut outcome = outcome2;
                // let _approval = dispatcher.approve(get_contract_address(), amount);
                let txn: bool = dispatcher
                    .transfer_from(get_caller_address(), get_contract_address(), amount);
                dispatcher
                    .transfer_from(
                        get_contract_address(),
                        self.treasuryWallet.read(),
                        amount * PLATFORM_FEE * one / 100
                    );
                outcome.boughtShares = outcome.boughtShares
                    + (amount * one - amount * one * PLATFORM_FEE / 100);
                let marketClone = self.markets.read(marketId);
                let moneyInPool = marketClone.moneyInPool
                    + amount * one
                    - amount * PLATFORM_FEE * one / 100;
                let marketNew = Market {
                    outcomes: (outcome1, outcome), moneyInPool: moneyInPool, ..marketClone
                };
                self.markets.write(marketId, marketNew);
                let updatedOdds = self.calcOdds(marketId);
                let mut otherOutcome = outcome1;
                outcome.currentOdds = *updatedOdds.at(1);
                otherOutcome.currentOdds = *updatedOdds.at(0);
                let marketClone = self.markets.read(marketId);
                let oddsUpdatedMarket = Market { outcomes: (outcome, otherOutcome), ..marketClone };
                self.markets.write(marketId, oddsUpdatedMarket);
                self.userBet.write((get_caller_address(), marketId), outcome);
                self
                    .userPortfolio
                    .write(
                        (get_caller_address(), outcome),
                        UserPosition { amount: amount, hasClaimed: false }
                    );
                let updatedMarket = self.markets.read(marketId);
                self
                    .emit(
                        ShareBought {
                            user: get_caller_address(),
                            market: updatedMarket,
                            outcome: outcome,
                            amount: amount
                        }
                    );
                txn
            }
        }

        fn getTreasuryWallet(self: @ContractState) -> ContractAddress {
            assert!(get_caller_address() == self.owner.read(), "Only owner can read.");
            return self.treasuryWallet.read();
        }

        fn claimWinnings(ref self: ContractState, marketId: u256, receiver: ContractAddress) {
            assert!(marketId <= self.idx.read(), "Market does not exist");
            let market = self.markets.read(marketId);
            assert!(market.isSettled == true, "Market isn't settled.");
            let userOutcome: Outcome = self.userBet.read((receiver, marketId));
            let userPosition: UserPosition = self.userPortfolio.read((receiver, userOutcome));
            assert!(userPosition.hasClaimed == false, "User has already claimed winnings.");
            let mut winnings = 0;
            let winningOutcome = market.winningOutcome.unwrap();
            assert!(userOutcome == winningOutcome, "User didn't win!");
            winnings = userPosition.amount * market.moneyInPool / userOutcome.boughtShares;
            let dispatcher = IERC20Dispatcher { contract_address: market.betToken };
            dispatcher.transfer(receiver, winnings);
            self
                .userPortfolio
                .write(
                    (receiver, userOutcome),
                    UserPosition { amount: userPosition.amount, hasClaimed: true }
                );
            self
                .emit(
                    WinningsClaimed {
                        user: receiver, market: market, outcome: userOutcome, amount: winnings
                    }
                );
        }

        fn setTreasuryWallet(ref self: ContractState, wallet: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can set.');
            self.treasuryWallet.write(wallet);
        }

        fn settleMarket(ref self: ContractState, marketId: u256, winningOutcome: u8) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can settle markets.');
            let mut market = self.markets.read(marketId);
            market.isSettled = true;
            let (outcome1, outcome2) = market.outcomes;
            if winningOutcome == 0 {
                market.winningOutcome = Option::Some(outcome1);
            } else {
                market.winningOutcome = Option::Some(outcome2);
            }
            self.markets.write(marketId, market);
            let currentMarket = self.markets.read(marketId);
            self.emit(MarketSettled { market: currentMarket });
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

        fn getOwner(self: @ContractState) -> ContractAddress {
            return self.owner.read();
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

        fn calcProbabilty(self: @ContractState, marketId: u256, outcome: Outcome) -> u256 {
            let market = self.markets.read(marketId);
            let (outcome1, outcome2) = market.outcomes;
            let totalShares = outcome1.boughtShares + outcome2.boughtShares;
            let outcomeShares = outcome.boughtShares;
            return outcomeShares / totalShares;
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
