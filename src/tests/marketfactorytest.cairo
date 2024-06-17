use snforge_std::{declare, start_mock_call, test_address, ContractClassTrait};
use starknet::{ContractAddress, contract_address_const, get_caller_address};
use raize_contracts::MarketFactory::{IMarketFactoryDispatcher, IMarketFactoryDispatcherTrait};
use raize_contracts::MarketFactory::{Outcome, Market};
use openzeppelin::tests::mocks::erc20_mocks::{CamelERC20Mock};
use openzeppelin::token::erc20::interface::{
    IERC20Camel, IERC20CamelDispatcher, IERC20CamelDispatcherTrait
};
use core::fmt::Debug;
use array::ArrayTrait;
use core::traits::Into;
use core::result::{ResultTrait};
use openzeppelin::utils::serde::SerializedAppend;
use core::pedersen::pedersen;
use starknet::testing::{set_contract_address, set_caller_address};
const PRECISION: u256 = 1_000_000_000_000_000_000;

#[derive(Drop, Serde)]
struct ERC20ConstructorArguments {
    name: felt252,
    symbol: felt252,
    initial_supply: u256,
    recipient: ContractAddress
}

fn deploy(contract_class_hash: felt252, calldata: Array<felt252>) -> ContractAddress {
    let (address, _) = starknet::syscalls::deploy_syscall(
        contract_class_hash.try_into().unwrap(), 0, calldata.span(), false
    )
        .unwrap_syscall();
    address
}

fn deploy_token(recepient: ContractAddress, amount: u256) -> ContractAddress {
    let erc20 = deploy(
        CamelERC20Mock::TEST_CLASS_HASH,
        ERC20ConstructorArgumentsImpl::new(recepient, amount).to_calldata()
    );
    erc20
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


#[test]
fn fakeERCDeployment() {
    let erc20 = deploy_token(get_caller_address(), 10000);
    assert_eq!(erc20, test_address());
}
// fn createMarket() {
//     let contract = declare("MarketFactory").unwrap();
//     let (contract_deploy_address, _) = contract.deploy(@array![]).unwrap();

//     let addr: ContractAddress = contract_address_const::<
//         0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
//     >();

//     // Create a Dispatcher object that will allow interacting with the deployed contract
//     let dispatcher = IMarketFactoryDispatcher { contract_address: contract_deploy_address };

//     dispatcher
//         .createMarket("Will it rain tomorrow?", ('Yes', 'No'), addr, 'Life');

//     let marketCount = dispatcher.getMarketCount();

//     assert(marketCount == 1, 'market count should be 1');
// }

// // #[test]

// fn shouldAcceptBets() {

//     let (contract_deplot_address, _) = contract.deploy(@array![]).unwrap();

//     let addr: ContractAddress = contract_address_const::<
//         0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
//     >();
// }


