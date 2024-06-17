use snforge_std::{declare, start_mock_call, test_address, ContractClassTrait};
use starknet::{ContractAddress, contract_address_const, get_caller_address};
use raize_contracts::MarketFactory::{IMarketFactoryDispatcher, IMarketFactoryDispatcherTrait};
use raize_contracts::MarketFactory::{Outcome, Market};
use raize_contracts::erc20::erc20_mocks::{CamelERC20Mock};
use openzeppelin::token::erc20::interface::{
    IERC20Camel, IERC20CamelDispatcher, IERC20CamelDispatcherTrait
};
use core::fmt::Debug;
use core::array::ArrayTrait;
use core::traits::Into;
use core::result::{ResultTrait};
use openzeppelin::utils::serde::SerializedAppend;
use core::pedersen::pedersen;
use starknet::testing::{set_contract_address, set_caller_address};
use core::starknet::SyscallResultTrait;
const PRECISION: u256 = 1_000_000_000_000_000_000;

#[derive(Drop, Serde)]
struct ERC20ConstructorArguments {
    name: felt252,
    symbol: felt252,
    initial_supply: u256,
    recipient: ContractAddress
}

fn deploy_token(recepient: ContractAddress, amount: u256) -> ContractAddress {
    let erc20_class_hash = declare("CamelERC20Mock").unwrap();
    let calldata = ERC20ConstructorArgumentsImpl::new(recepient, amount).to_calldata();

    let (contract_address, _) = erc20_class_hash.deploy(@calldata).unwrap();
    contract_address
}

#[generate_trait]
impl ERC20ConstructorArgumentsImpl of ERC20ConstructorArgumentsTrait {
    fn new(recipient: ContractAddress, initial_supply: u256) -> ERC20ConstructorArguments {
        ERC20ConstructorArguments {
            name: 0_felt252, symbol: 0_felt252, initial_supply: initial_supply, recipient: recipient
        }
    }
    fn to_calldata(self: ERC20ConstructorArguments) -> Array<felt252> {
        let mut calldata = array![];
        calldata.append_serde(self.name);
        calldata.append_serde(self.symbol);
        calldata.append_serde(self.initial_supply);
        calldata.append_serde(self.recipient);
        calldata
    }
}

fn fakeERCDeployment() -> ContractAddress {
    let amount: u256 = 10000;
    let erc20 = deploy_token(get_caller_address(), amount);
    erc20
}

fn deployMarketContract() -> ContractAddress {
    let contract = declare("MarketFactory").unwrap();
    let (contract_deploy_address, _) = contract.deploy(@array![]).unwrap();
    contract_deploy_address
}

// fake token address -> 0x4661696c656420746f20646573657269616c697a6520706172616d202332

#[test]
fn createMarket() {
    let marketContract = deployMarketContract();
    let tokenAddress = fakeERCDeployment();

    let dispatcher = IMarketFactoryDispatcher { contract_address: marketContract };

    dispatcher.createMarket("Will it rain tomorrow?", ('Yes', 'No'), tokenAddress, 'Life');

    let marketCount = dispatcher.getMarketCount();

    assert(marketCount == 1, 'market count should be 1');
}

// // #[test]

fn shouldAcceptBets() {
    let marketContract = deployMarketContract();
    let tokenAddress = fakeERCDeployment();
}

