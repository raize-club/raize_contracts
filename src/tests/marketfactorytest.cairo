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
    let mut calldata = ArrayTrait::new();
    calldata.append(get_caller_address().try_into().unwrap());
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

#[test]
fn createMarket() {
    let marketContract = deployMarketContract();
    let tokenAddress = fakeERCDeployment();

    let dispatcher = IMarketFactoryDispatcher { contract_address: marketContract };

    dispatcher.createMarket("Will it rain tomorrow?", ('Yes', 'No'), tokenAddress, 'Life');

    let marketCount = dispatcher.getMarketCount();

    assert(marketCount == 1, 'market count should be 1');
}


#[test]
fn shouldAcceptBets() {
    let marketContract = deployMarketContract();
    let tokenAddress = fakeERCDeployment();

    let dispatcher = IMarketFactoryDispatcher { contract_address: marketContract };

    let tokenDispatcher = IERC20Dispatcher { contract_address: tokenAddress };

    dispatcher.createMarket("Will it rain tomorrow?", ('Yes', 'No'), tokenAddress, 'Life');

    assert_eq!(tokenDispatcher.balance_of(get_caller_address()), 10000);
// dispatcher.buyShares(0, 0, 10);
}

