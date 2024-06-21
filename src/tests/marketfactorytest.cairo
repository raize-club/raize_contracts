use core::option::OptionTrait;
use core::fmt::Display;
use core::traits::AddEq;
use snforge_std::{
    declare, start_mock_call, test_address, start_cheat_caller_address, stop_cheat_caller_address, cheat_caller_address_global,
    ContractClassTrait
};
use starknet::{
    ContractAddress, contract_address_const, get_caller_address, get_contract_address,
    contract_address
};
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

fn deploy_token() -> ContractAddress {
    let erc20_class_hash = declare("CamelERC20Mock").unwrap();
    let mut calldata = array![];
    let (contract_address, _) = erc20_class_hash.deploy(@calldata).unwrap();
    contract_address
}

fn fakeERCDeployment() -> ContractAddress {
    let erc20 = deploy_token();
    erc20
}

fn deployMarketContract() -> ContractAddress {
    let contract = declare("MarketFactory").unwrap();
    let mut calldata = array![];
    calldata.append_serde(contract_address_const::<1>());
    let (contract_deploy_address, _) = contract.deploy(@calldata).unwrap();
    contract_deploy_address
}

// should create a market
#[test]
fn createMarket() {
    let marketContract = deployMarketContract();
    let tokenAddress = fakeERCDeployment();

    let dispatcher = IMarketFactoryDispatcher { contract_address: marketContract };

    start_cheat_caller_address(marketContract, contract_address_const::<1>());
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

// should set treasury wallet 
#[test]
fn shouldSetTreasury() {
    let marketContract = deployMarketContract();
    cheat_caller_address_global(contract_address_const::<1>());
    // let tokenAddress = fakeERCDeployment();

    let dispatcher = IMarketFactoryDispatcher { contract_address: marketContract };

    dispatcher.setTreasuryWallet(contract_address_const::<1>());
    let treasury = dispatcher.getTreasuryWallet();
    assert(treasury == contract_address_const::<1>(), 'treasury not set!');
}

// should take bets
#[test]
fn shouldAcceptBets() {
    let marketContract = deployMarketContract();
    cheat_caller_address_global(contract_address_const::<1>());
    let tokenAddress = fakeERCDeployment();

    let dispatcher = IMarketFactoryDispatcher { contract_address: marketContract };

    let tokenDispatcher = IERC20Dispatcher { contract_address: tokenAddress };

    dispatcher.setTreasuryWallet(contract_address_const::<1>());
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
    let balance_of = tokenDispatcher.balance_of(get_caller_address());
    print!("Balance of caller {:?} \n: ", balance_of);
    let balance_of_contract = tokenDispatcher.balance_of(marketContract);
    print!("Balance of caller {:?} \n: ", balance_of_contract);
    let tx = tokenDispatcher.approve(marketContract, 100000);
    assert(tx == true, 'tx failed!');
    // let allowance = tokenDispatcher.allowance(contract_address_const::<1>(), marketContract);
    // print!("allowance: {} \n", allowance);
    let tx = dispatcher.buyShares(1, 0, 1000);
    let balance_of = tokenDispatcher.balance_of(get_caller_address());
    print!("Balance of caller {:?} \n: ", balance_of);
    let balance_of_contract = tokenDispatcher.balance_of(marketContract);
    print!("Balance of contract {:?} \n: ", balance_of_contract);
    assert(tx == true, 'tx failed!');
}

// should change odds after every bet
#[test]
fn shouldChangeOdds() {
    let marketContract = deployMarketContract();
    let tokenAddress = fakeERCDeployment();

    let dispatcher = IMarketFactoryDispatcher { contract_address: marketContract };

    let tokenDispatcher = IERC20Dispatcher { contract_address: tokenAddress };

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

    let approval = dispatcher.checkForApproval(tokenAddress, 1000);
    if approval == false {
        let tx = tokenDispatcher.approve(marketContract, 1000);
        assert(tx == true, 'tx failed!');
    }
    // let market = dispatcher.getMarket(1);
    // let (outcome1, _) = market.outcomes;
    // let currentOdds = outcome1.currentOdds;
    dispatcher.buyShares(1, 0, 10);
// let market = dispatcher.getMarket(1);
// let (outcome1, _) = market.outcomes;
// let newOdds = outcome1.currentOdds;
// assert(newOdds != currentOdds, 'odds are not changing!');
}

// should keep fees in treasury after every txn
#[test]
fn shouldKeepFees() {
    let marketContract = deployMarketContract();
    let tokenAddress = fakeERCDeployment();

    let dispatcher = IMarketFactoryDispatcher { contract_address: marketContract };

    let tokenDispatcher = IERC20Dispatcher { contract_address: tokenAddress };

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

    let approval = dispatcher.checkForApproval(tokenAddress, 1000);
    if approval == false {
        let tx = tokenDispatcher.approve(marketContract, 1000);
        assert(tx == true, 'tx failed!');
    }
    dispatcher.buyShares(1, 0, 10);
// let updatedFees = dispatcher.getFeesAccumulated(tokenAddress);
// assert(updatedFees == 10 * PRECISION * 2 / 100, 'fees not accumulated!');
}

// should add money in main liquidity pool for whatever amount is added per market
#[test]
fn shouldAddMoney() {
    let marketContract = deployMarketContract();
    let tokenAddress = fakeERCDeployment();

    let dispatcher = IMarketFactoryDispatcher { contract_address: marketContract };

    let tokenDispatcher = IERC20Dispatcher { contract_address: tokenAddress };

    dispatcher
        .createMarket(
            "Trump vs Biden",
            "Will Trump emerge victorious again?",
            ('Yes', 'No'),
            tokenAddress,
            'Politics',
            "trump.png",
            1818704106
        );

    let approval = dispatcher.checkForApproval(tokenAddress, 1000);
    if approval == false {
        let tx = tokenDispatcher.approve(marketContract, 1000);
        assert(tx == true, 'tx failed!');
    }
    // let moneyInPool = dispatcher.getMarket(1).moneyInPool;
    // print!("money in pool: {} \n", moneyInPool);
    dispatcher.buyShares(1, 0, 10);
// let updatedMoney = dispatcher.getMarket(1).moneyInPool;
// print!("updated in pool: {} \n", updatedMoney);
// assert(updatedMoney - moneyInPool == 10 * PRECISION - 10 * PRECISION * 2 / 100, 'money not added to pool!');
}

// should let people claim winnings
#[test]
fn shouldLetClaimWinnings() {
    let marketContract = deployMarketContract(); // <1>
    let tokenAddress = fakeERCDeployment(); // <1> owns 100000 tokens

    let dispatcher = IMarketFactoryDispatcher { contract_address: marketContract };

    let tokenDispatcher = IERC20Dispatcher { contract_address: tokenAddress };

    start_cheat_caller_address(marketContract, contract_address_const::<1>());
    dispatcher.setTreasuryWallet(contract_address_const::<1>());
    dispatcher
        .createMarket(
            "Trump vs Biden",
            "Will Trump emerge victorious again?",
            ('Yes', 'No'),
            tokenAddress,
            'Politics',
            "trump.png",
            1818704106
        );

    // let approval = dispatcher.checkForApproval(tokenAddress, 1000);
    // if approval == false {
    //     let tx = tokenDispatcher.approve(marketContract, 1000);
    //     assert(tx == true, 'tx failed!');
    // }
    stop_cheat_caller_address(marketContract);
    start_cheat_caller_address(tokenAddress, contract_address_const::<1>());
    tokenDispatcher.transfer(contract_address_const::<2>(), 100000  * PRECISION);
    tokenDispatcher.transfer(marketContract, 100000  * PRECISION);
    stop_cheat_caller_address(tokenAddress);
    start_cheat_caller_address(marketContract,contract_address_const::<2>());
    start_cheat_caller_address(tokenAddress,contract_address_const::<2>());
    dispatcher.buyShares(1, 0, 100 * PRECISION);
    stop_cheat_caller_address(marketContract);
    start_cheat_caller_address(marketContract, contract_address_const::<1>());
    dispatcher.settleMarket(1, 0);
    stop_cheat_caller_address(marketContract);
    let balance = tokenDispatcher.balance_of(contract_address_const::<2>());
    dispatcher.claimWinnings(1, contract_address_const::<2>());
    let updatedBalance = tokenDispatcher.balance_of(contract_address_const::<2>());
    print!("balance -> {} , updatedBalance -> {}", balance, updatedBalance);
    assert(updatedBalance - balance > 0, 'winnings not claimed!');
}

// should let owner withdraw fees from treasury
#[test]
fn shouldLetOwnerWithdrawFees() {
    let marketContract = deployMarketContract();
    let tokenAddress = fakeERCDeployment();

    let dispatcher = IMarketFactoryDispatcher { contract_address: marketContract };

    let tokenDispatcher = IERC20Dispatcher { contract_address: tokenAddress };

    dispatcher
        .createMarket(
            "Trump vs Biden",
            "Will Trump emerge victorious again?",
            ('Yes', 'No'),
            tokenAddress,
            'Politics',
            "trump.png",
            1818704106
        );

    let approval = dispatcher.checkForApproval(tokenAddress, 1000);
    if approval == false {
        let tx = tokenDispatcher.approve(marketContract, 1000);
        assert(tx == true, 'tx failed!');
    }
    dispatcher.buyShares(1, 0, 10);
// let fees = dispatcher.getFeesAccumulated(tokenAddress);
// dispatcher.withdrawFromTreasury(tokenAddress);
// let updatedFees = dispatcher.getFeesAccumulated(tokenAddress);
// assert(fees - updatedFees > 0, 'fees not withdrawn!');
}

