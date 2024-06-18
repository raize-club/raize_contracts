use snforge_std::{declare, start_mock_call, test_address, ContractClassTrait};
use starknet::{ContractAddress, contract_address_const, get_caller_address};
use raize_contracts::MarketFactory::{IMarketFactoryDispatcher, IMarketFactoryDispatcherTrait};
use raize_contracts::MarketFactory::{Outcome, Market};
use raize_contracts::erc20::erc20_mocks::{CamelERC20Mock};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use core::fmt::Debug;
use core::array::ArrayTrait;
use core::traits::Into;
use core::traits::TryInto;
use core::result::{ResultTrait};
use openzeppelin::utils::serde::SerializedAppend;
use core::pedersen::pedersen;
use starknet::testing::{set_contract_address, set_caller_address};
use core::starknet::SyscallResultTrait;
const PRECISION: u256 = 1_000_000_000_000_000_000;

// #[derive(Drop, Serde)]
// struct ERC20ConstructorArguments {
//     initial_supply: u256,
//     recipient: ContractAddress
// }

fn deploy_token() -> ContractAddress {
    let erc20_class_hash = declare("CamelERC20Mock").unwrap();
    let mut calldata = array![];
    let (contract_address, _) = erc20_class_hash.deploy(@calldata).unwrap();
    contract_address
}

// #[generate_trait]
// impl ERC20ConstructorArgumentsImpl of ERC20ConstructorArgumentsTrait {
//     fn to_calldata(self: ERC20ConstructorArguments) -> Array<felt252> {
//         let mut calldata = array![];
//         // calldata.append_serde(self.name);
//         // calldata.append_serde(self.symbol);
//         // calldata.append_serde(self.initial_supply);
//         // calldata.append_serde(self.recipient);
//         calldata
//     }
// }

fn fakeERCDeployment() -> ContractAddress {
    let erc20 = deploy_token();
    erc20
}

fn deployMarketContract() -> ContractAddress {
    let contract = declare("MarketFactory").unwrap();
    let (contract_deploy_address, _) = contract.deploy(@array![]).unwrap();
    contract_deploy_address
}

// should create a market
#[test]
fn createMarket() {
    let marketContract = deployMarketContract();
    let tokenAddress = fakeERCDeployment();

    let dispatcher = IMarketFactoryDispatcher { contract_address: marketContract };

    dispatcher
        .createMarket(
            "Trump vs Biden",
            "Will Trump emerge victorious again?",
            ('Yes', 'No'),
            tokenAddress,
            'Life',
            "trump.png",
            1818704106
        );

    let marketCount = dispatcher.getMarketCount();

    assert(marketCount == 1, 'market count should be 1');
}


// should take bets
#[test]
fn shouldAcceptBets() {
    let marketContract = deployMarketContract();
    let tokenAddress = fakeERCDeployment();

    let dispatcher = IMarketFactoryDispatcher { contract_address: marketContract };

    dispatcher
        .createMarket(
            "Trump vs Biden",
            "Will Trump emerge victorious again?",
            ('Yes', 'No'),
            tokenAddress,
            'Life',
            "trump.png",
            1818704106
        );

    dispatcher.buyShares(0, 0, 10);
}

// should change odds after every bet
// should keep fees in treasury after every txn
// should add money in main liquidity pool for whatever amount is added per market
// should let people claim winnings
// should let owner withdraw fees from treasury

