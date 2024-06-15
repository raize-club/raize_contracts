use starknet::ContractAddress;

#[derive(Drop, Serde, starknet::Store)]
struct Market {
    name: ByteArray,
    outcomes: (Outcome, Outcome),
    isSettled: bool,
    isActive: bool,
    betToken: ContractAddress,
    winningOutcome: Option<Outcome>,
    moneyInPool: u256,
}

#[derive(Drop, Copy, Serde, starknet::Store, PartialEq)]
struct Outcome {
    name: felt252,
    currentOdds: u256,
    boughtShares: u256,
}


#[starknet::interface]
trait IMarketFactory<TContractState> {
    fn createMarket(
        ref self: TContractState, name: ByteArray, outcomes: (Outcome, Outcome), moneyInPool: u256, betToken: ContractAddress
    ); //done

    fn getMarketCount(self: @TContractState) -> u256; //done

    fn mintShares(
        ref self: TContractState,
        marketId: u256,
        tokenToMint: u8,
        receiver: ContractAddress,
        amount: u256
    ) -> bool; //done

    fn burnShares(
        ref self: TContractState,
        marketId: u256,
        tokenToBurn: u8,
        receiver: ContractAddress,
    ) -> bool; // done

    fn settleMarket(ref self: TContractState, marketId: u256, winningOutcome: Outcome); // done

    fn toggleMarketStatus(ref self: TContractState, marketId: u256); //done

    fn claimWinnings(ref self: TContractState, marketId: u256, receiver: ContractAddress); // done

    fn getMarket(self: @TContractState, marketId: u256) -> Market; //done

    fn updateTreasuryAccount(ref self: TContractState, newTreasury: ContractAddress); // done
}

trait IMarketFactoryImpl<TContractState> {
    fn calcProbabilty(ref self: TContractState, marketId: u256, outcome: Outcome) -> u256;

    fn calcOdds(ref self: TContractState, marketId: u256, margin: u256) -> Array<u256>;

    fn marginAdjustedOdds(
        ref self: TContractState, marketId: u256, probabilities: @Array<u256>, margin: u256
    ) -> Array<u256>;

    fn isMarketResolved(self: @TContractState, marketId: u256) -> bool;
}

#[starknet::contract]
mod MarketFactory {
    use openzeppelin::token::erc20::interface::IERC20DispatcherTrait;
use core::box::BoxTrait;
use core::option::OptionTrait;
use core::array::ArrayTrait;
use super::{Market, Outcome};
    use starknet::{ContractAddress, get_caller_address};
    use core::num::traits::zero::Zero;
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;

    const one: u256 = 1_000_000_000_000_000_000;
    const MAX_ITERATIONS: u16 = 25;
    #[storage]
    struct Storage {
        userBet: LegacyMap::<(ContractAddress, u256), Outcome>,
        // markets: Array<Market>
        markets: LegacyMap::<u256, Market>,
        idx: u256,
        treasury: ContractAddress,
        userPortfolio: LegacyMap::<
            (ContractAddress, Outcome), u256
        >, // read outcome with market id and user name, then read portfolio using contract address and outcome.
    }

    #[constructor]
    fn constructor(ref self: ContractState, treasury: ContractAddress) {
        self.treasury.write(treasury);
    }

    impl MarketFactoryImpl of super::IMarketFactoryImpl<ContractState> {
        fn isMarketResolved(self: @ContractState, marketId: u256) -> bool {
            let market = self.markets.read(marketId);
            return market.isSettled;
        }

        fn calcProbabilty(ref self: ContractState, marketId: u256, outcome: Outcome) -> u256 {
            let market = self.markets.read(marketId);
            let (outcome1, outcome2) = market.outcomes;
            let totalShares = outcome1.boughtShares + outcome2.boughtShares;
            let outcomeShares = outcome.boughtShares;
            return outcomeShares / totalShares;
        }

        fn calcOdds(ref self: ContractState, marketId: u256, margin: u256) -> Array<u256> {
            let market = self.markets.read(marketId);
            let (outcome1, outcome2) = market.outcomes;
            if margin > 0 {
                let mut probabilities: Array<u256> = ArrayTrait::new();
                probabilities.append(self.calcProbabilty(marketId, outcome1));
                probabilities.append(self.calcProbabilty(marketId, outcome2));
                let mut odds: Array<u256> = ArrayTrait::new();
                odds.append(outcome1.currentOdds);
                odds.append(outcome2.currentOdds);
                let adjustedOdds: Array<u256> = self.marginAdjustedOdds(marketId, @probabilities, margin);
                adjustedOdds
            }
            else {
                let mut odds: Array<u256> = ArrayTrait::new();
                let mut i: usize = 0;
                loop {
                    if i > 1 {
                        break;
                    }
                    let odd = (outcome1.boughtShares + outcome2.boughtShares) / outcome1.boughtShares;
                    odds.append(odd);
                    i += 1;
                };
                odds
            }
        }

        fn marginAdjustedOdds(
            ref self: ContractState,marketId: u256, probabilities: @Array<u256>, margin: u256
        ) -> Array<u256> {
            let length: usize = probabilities.len();
            let mut odds: Array<u256> = ArrayTrait::new();
            let mut spreads: Array<u256> = ArrayTrait::new();
            let mut i: usize = 0;
            loop {
                if i == length {
                    break;
                }
                let spread = (one - *probabilities.at(i) * margin);
                spreads.append(spread);
                i += 1;
            };
            let mut iteration: u16 = 0;
            loop {
                if iteration == MAX_ITERATIONS {
                    break;
                }
                let mut oddsSpread: u256 = 0;
                {
                    let mut spread: u256 = 0;
                    let mut j: usize = 0; 
                    loop {
                        if j == length {
                            break;
                        }
                        let odds_ = (one - 0)/ *probabilities.at(j);
                        // let odds_ = (one - *spreads.at(j))/ *probabilities.at(j);
                        odds.append(odds_);
                        spread += one / odds_;
                        j += 1;
                    };
                    oddsSpread = one - one / spread;
                }
                // let mut iterator: usize = 0;
                // let mut refinedSpread: Array<u256> = ArrayTrait::new();
                // loop {
                //     if iterator == length {
                //         break;
                //     }
                //     // let spread_ = *spreads.at(iterator) + (one - *spreads.at(iterator) - *probabilities.at(iterator)) * sigmoid((margin * *spreads.at(iterator)) / (one - one / *odds.at(iterator))/ ((one - margin) / oddsSpread));
                //     refinedSpread.append(spread_);
                //     iterator += 1;
                // };
            };
            odds
        }
    }

    fn sigmoid(x: u256) -> u256 {
        return (1 * x) / (1 + x);
    }

    fn createShareTokens(
        ref self: ContractState, names: (felt252, felt252), boughtShares: u256
    ) -> (Outcome, Outcome) {
        let (name1, name2) = names;
        let mut token1 = Outcome { name: name1, boughtShares: boughtShares, currentOdds: 2 };
        let mut token2 = Outcome { name: name2, boughtShares: boughtShares, currentOdds: 2 };

        let tokens = (token1, token2);

        return tokens;
    }


    #[abi(embed_v0)]
    impl MarketFactory of super::IMarketFactory<ContractState> {
        fn createMarket(
            ref self: ContractState,
            name: ByteArray,
            outcomes: (Outcome, Outcome),
            moneyInPool: u256,
            betToken: ContractAddress
        ) {
            let market = Market {
                name,
                outcomes,
                isSettled: false,
                isActive: true,
                winningOutcome: Option::None,
                betToken: betToken,
                moneyInPool
            };
            self.markets.write(self.idx.read(), market);
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

        fn mintShares(
            ref self: ContractState,
            marketId: u256,
            tokenToMint: u8,
            receiver: ContractAddress,
            amount: u256
        ) -> bool {
            let market = self.markets.read(marketId);
            let token = self.userBet.read((receiver, marketId));
            let (outcome1, outcome2) = market.outcomes;
            if tokenToMint == 0 {
                if token.boughtShares.is_zero() {
                    let outcome = outcome1;
                    let dispatcher = IERC20Dispatcher { contract_address: market.betToken };
                    // token approval and transfer to treasury from user.
                    
                    let _approval = dispatcher.approve(self.treasury.read(), amount);
                    let txn: bool = dispatcher.transfer_from(get_caller_address(), self.treasury.read(), amount);
                    self.userBet.write((receiver, marketId), outcome);
                    self.userPortfolio.write((receiver, outcome), amount);
                    txn
                } else {
                    // panic!("User already has a bet in this market");
                    false
                }
            } else {
                if token.boughtShares.is_zero() {
                    let outcome = outcome2;
                    self.userBet.write((receiver, marketId), outcome);
                    true
                } else {
                    // panic!("User already has a bet in this market");
                    false
                }
            }
        }

        fn burnShares(
            ref self: ContractState,
            marketId: u256,
            tokenToBurn: u8,
            receiver: ContractAddress,
        ) -> bool {
            let token = self.userBet.read((receiver, marketId));
            let betAmount = self.userPortfolio.read((receiver, token));
            if betAmount.is_zero() {
                false
            } else {
                // token transfer to user from treasury.
                self.userPortfolio.write((receiver, token), 0);
                true
            }
        }

        fn claimWinnings(ref self: ContractState, marketId: u256, receiver: ContractAddress) {
            assert!(marketId <= self.idx.read(), "Market does not exist");
            let market = self.markets.read(marketId);
            let userOutcome: Outcome = self.userBet.read((receiver, marketId));
            let mut betAmount: u256 = self.userPortfolio.read((receiver, userOutcome));
            let mut winnings = 0;
            if market.isSettled {
                let winningOutcome = market.winningOutcome.unwrap();
                if userOutcome == winningOutcome {
                    winnings = betAmount * market.moneyInPool / userOutcome.boughtShares;
                }
                self.userPortfolio.write((receiver, userOutcome), 0);
            }
        }

        fn settleMarket(ref self: ContractState, marketId: u256, winningOutcome: Outcome) {
            let mut market = self.markets.read(marketId);
            market.isSettled = true;
            market.winningOutcome = Option::Some(winningOutcome);
            self.markets.write(marketId, market);
        }

        fn updateTreasuryAccount(ref self: ContractState, newTreasury: ContractAddress) {
            self.treasury.write(newTreasury);
        }
    }


}