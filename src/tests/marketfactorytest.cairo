use core::fmt::Display;
use core::traits::AddEq;
use snforge_std::{declare, start_mock_call, test_address, ContractClassTrait};
use starknet::{ContractAddress, contract_address_const, get_caller_address, get_contract_address};
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
    
    let approval =  dispatcher.checkForApproval(tokenAddress, 1000);
    if approval == false {
        let tx = tokenDispatcher.approve(marketContract, 1000);
        assert(tx == true, 'tx failed!');
    }
    let tx = dispatcher.buyShares(1, 0, 100); 
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
    
    let approval =  dispatcher.checkForApproval(tokenAddress, 1000);
    if approval == false {
        let tx = tokenDispatcher.approve(marketContract, 1000);
        assert(tx == true, 'tx failed!');
    }
    let market = dispatcher.getMarket(1);
    let (outcome1, _) = market.outcomes;
    let currentOdds = outcome1.currentOdds;
    dispatcher.buyShares(1, 0, 10);
    let market = dispatcher.getMarket(1);
    let (outcome1, _) = market.outcomes;
    let newOdds = outcome1.currentOdds;
    assert(newOdds != currentOdds, 'odds are not changing!');
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
    
    let approval =  dispatcher.checkForApproval(tokenAddress, 1000);
    if approval == false {
        let tx = tokenDispatcher.approve(marketContract, 1000);
        assert(tx == true, 'tx failed!');
    }
    dispatcher.buyShares(1, 0, 10);
    let updatedFees = dispatcher.getFeesAccumulated(tokenAddress);
    assert(updatedFees == 10 * PRECISION * 2 / 100, 'fees not accumulated!');
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
    
    let approval =  dispatcher.checkForApproval(tokenAddress, 1000);
    if approval == false {
        let tx = tokenDispatcher.approve(marketContract, 1000);
        assert(tx == true, 'tx failed!');
    }
    let moneyInPool = dispatcher.getMarket(1).moneyInPool;
    print!("money in pool: {} \n", moneyInPool);
    dispatcher.buyShares(1, 0, 10);
    let updatedMoney = dispatcher.getMarket(1).moneyInPool;
    print!("updated in pool: {} \n", updatedMoney);
    assert(updatedMoney - moneyInPool == 10 * PRECISION - 10 * PRECISION * 2 / 100, 'money not added to pool!');
}

// should let people claim winnings
#[test]
fn shouldLetClaimWinnings() {
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
    
    let approval =  dispatcher.checkForApproval(tokenAddress, 1000);
    if approval == false {
        let tx = tokenDispatcher.approve(marketContract, 1000);
        assert(tx == true, 'tx failed!');
    }
    dispatcher.buyShares(1, 0, 10);
    dispatcher.settleMarket(1, 0);
    let balance = tokenDispatcher.balance_of(get_contract_address());
    dispatcher.claimWinnings(1, get_contract_address());
    let updatedBalance = tokenDispatcher.balance_of(get_contract_address());
    assert(updatedBalance - balance == 8, 'winnings not claimed!');
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
    
    let approval =  dispatcher.checkForApproval(tokenAddress, 1000);
    if approval == false {
        let tx = tokenDispatcher.approve(marketContract, 1000);
        assert(tx == true, 'tx failed!');
    }
    dispatcher.buyShares(1, 0, 10);
    let fees = dispatcher.getFeesAccumulated(tokenAddress);
    dispatcher.withdrawFromTreasury(tokenAddress);
    let updatedFees = dispatcher.getFeesAccumulated(tokenAddress);
    assert(fees - updatedFees > 0, 'fees not withdrawn!');
}


