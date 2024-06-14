use starknet::ContractAddress;
mod OwnableERC20;
#[derive(Drop, Serde, starknet::Store)]
struct Market {
    name: ByteArray,
    outcomes: Array<ContractAddress>,
    // outcomes: Array<ContractAddress>,
    isSettled: bool,
    isActive: bool,
    winningOutcome: ContractAddress,
    moneyInPool: u256,
}

#[starknet::interface]
trait IMarketFactory<TContractState> {
    fn createMarket(
        ref self: TContractState,
        name: ByteArray,
        outcomes: Array<ContractAddress>,
        moneyInPool: u256
    );

    fn getMarketCount(self: @TContractState) -> u256;

    fn mintShares(
        ref self: TContractState,
        marketId: u256,
        tokenToMint: u8,
        receiver: ContractAddress,
        amount: u256
    ) -> bool;

    fn burnShares(
        ref self: TContractState,
        marketId: u256,
        tokenToBurn: u8,
        receiver: ContractAddress,
        amount: u256
    ) -> bool;

    fn settleMarket(ref self: TContractState, marketId: u256, winningOutcome: ContractAddress);

    fn toggleMarketStatus(ref self: TContractState, marketId: u256);

    fn claimWinnings(ref self: TContractState, marketId: u256, receiver: ContractAddress);

    fn calcCost(ref self: TContractState, marketId: u256, tokensToBuy: u8, amount: u256) -> u256;

    fn calcProbabilty(ref self: TContractState, marketId: u256, tokenContract: ContractAddress ) -> u256;

    fn calcOdds(ref self: TContractState, marketId: u256, margin: u16) -> u256;

    fn marginAdjustedOdds(ref self: TContractState, probabilities: Array<u256>, margin: u256, odds: Array<u256>);

    fn activateMarket(ref self: TContractState, marketId: u256);

    fn getMarket(self: @TContractState, marketId: u256) -> Market;
}


#[starknet::contract]
mod MarketFactory {
    use super::Market;
    use starknet::{ContractAddress,contract_address_const};
    use core::num::traits::Zero;
    #[storage]
    struct Storage {
        userBet: LegacyMap::<(ContractAddress, u256), ContractAddress>,
        // markets: Array<Market>
        markets : LegacyMap::<u256,Market>,
        idx : u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[generate_trait]
    impl MarketFactoryImpl of MarketFactoryInternal {
        fn isMarketResolved( self: @ContractState,marketId: u256) -> bool {
            let market = self.markets.read(marketId);
            return market.isSettled;
        }
    }
    

    #[abi(embed_v0)]
    impl MarketFactory of super::IMarketFactory<ContractState> {
        fn createMarket(
            ref self: ContractState,
            name: ByteArray,
            outcomes: Array<ContractAddress>,
            moneyInPool: u256
        ) {
            let market = Market {
                name, outcomes, isSettled: false, isActive: true, winningOutcome: contract_address_const::<0>(),moneyInPool
            };
            self.markets.write( self.idx.read(),market);
        }
        fn getMarket(self: @ContractState, marketId: u256) -> Market {
            return self.markets.read(marketId);
        }

        // fn createShareTokens(
        //     ref self: ContractState,
        //     names: Array<ByteArray>,
        //     symbols: Array<ByteArray>,
        //     owner: ContractAddress
        // ) -> Array<ContractAddress> {
        //     let numOutcomes = names.len();
        //     let mut tokens = ArrayTrait::<ContractAddress>::new();

        //     for i in 0..numOutcomes {
        //         let token = OwnableERC20::OwnedERC20::new(names[i], symbols[i], owner);
        //         tokens.push(token);
        //     }
        //     return tokens;
        // }
    }
    
}


// function createShareTokens(
//     string[] memory _names,
//     string[] memory _symbols,
//     address _owner
// ) internal returns (OwnedERC20[] memory) {
//     uint256 _numOutcomes = _names.length;
//     OwnedERC20[] memory _tokens = new OwnedERC20[](_numOutcomes);

//     for (uint256 _i = 0; _i < _numOutcomes; _i++) {
//         _tokens[_i] = new OwnedERC20(_names[_i], _symbols[_i], _owner);
//     }
//     return _tokens;
// }