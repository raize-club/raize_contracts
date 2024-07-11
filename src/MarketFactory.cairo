use starknet::{ContractAddress, ClassHash};
use pragma_lib::types::{AggregationMode, DataType, PragmaPricesResponse};

#[derive(Drop, Serde, starknet::Store)]
pub struct Market {
    name: ByteArray,
    market_id: u256,
    description: ByteArray,
    outcomes: (Outcome, Outcome),
    category: felt252,
    image: ByteArray,
    is_settled: bool,
    is_active: bool,
    deadline: u64,
    winning_outcome: Option<Outcome>,
    money_in_pool: u256,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct CryptoMarket {
    name: ByteArray,
    market_id: u256,
    description: ByteArray,
    outcomes: (Outcome, Outcome),
    category: felt252,
    image: ByteArray,
    is_settled: bool,
    is_active: bool,
    deadline: u64,
    winning_outcome: Option<Outcome>,
    money_in_pool: u256,
    conditions: u8, // 0 -> less than amount, 1 -> greater than amount. e.g.(0) -> will BTC go below $40,000?
    price_key: felt252,
    amount: u128
}


#[derive(Drop, Serde, starknet::Store)]
pub struct SportsMarket {
    name: ByteArray,
    market_id: u256,
    description: ByteArray,
    outcomes: (Outcome, Outcome),
    category: felt252,
    image: ByteArray,
    is_settled: bool,
    is_active: bool,
    deadline: u64,
    winning_outcome: Option<Outcome>,
    money_in_pool: u256,
    api_event_id: u64, // the settling market script will send an API request on the event id to fetch the results from the event, and settles the market accordingly
    is_home: bool,
}

#[derive(Copy, Serde, Drop, starknet::Store, PartialEq, Eq, Hash)]
pub struct Outcome {
    name: felt252,
    bought_shares: u256,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct UserPosition {
    amount: u256,
    has_claimed: bool,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct UserBet {
    outcome: Outcome,
    position: UserPosition
}

#[starknet::interface]
pub trait IMarketFactory<TContractState> {
    fn create_market(
        ref self: TContractState,
        name: ByteArray,
        description: ByteArray,
        outcomes: (felt252, felt252),
        category: felt252,
        image: ByteArray,
        deadline: u64,
    );

    fn create_crypto_market(
        ref self: TContractState,
        name: ByteArray,
        description: ByteArray,
        outcomes: (felt252, felt252),
        category: felt252,
        image: ByteArray,
        deadline: u64,
        conditions: u8,
        price_key: felt252,
        amount: u128,
    );

    fn create_sports_market(
        ref self: TContractState,
        name: ByteArray,
        description: ByteArray,
        outcomes: (felt252, felt252),
        category: felt252,
        image: ByteArray,
        deadline: u64,
        api_event_id: u64,
        is_home: bool,
    );

    fn get_market_count(self: @TContractState) -> u256;

    fn buy_shares(
        ref self: TContractState, market_id: u256, token_to_mint: u8, amount: u256, market_type: u8
    ) -> bool;

    fn settle_market(ref self: TContractState, market_id: u256, winning_outcome: u8);

    fn settle_crypto_market_manually(
        ref self: TContractState, market_id: u256, winning_outcome: u8
    );

    fn settle_sports_market_manually(
        ref self: TContractState, market_id: u256, winning_outcome: u8
    );

    fn claim_winnings(ref self: TContractState, market_id: u256, market_type: u8, bet_num: u8);

    fn get_market(self: @TContractState, market_id: u256) -> Market;

    fn get_all_markets(self: @TContractState) -> Array<Market>;

    fn get_crypto_market(self: @TContractState, market_id: u256) -> CryptoMarket;

    fn get_all_crypto_markets(self: @TContractState) -> Array<CryptoMarket>;

    fn get_sports_market(self: @TContractState, market_id: u256) -> SportsMarket;

    fn get_all_sports_markets(self: @TContractState) -> Array<SportsMarket>;

    fn settle_sports_market(
        ref self: TContractState, market_id: u256, winning_outcome: u8
    ); // returns 0 if condition was true, 1 if false

    fn get_user_markets(self: @TContractState, user: ContractAddress) -> Array<Market>;

    fn get_owner(self: @TContractState) -> ContractAddress;

    fn get_treasury_wallet(self: @TContractState) -> ContractAddress;

    fn set_treasury_wallet(ref self: TContractState, wallet: ContractAddress);

    fn upgrade(ref self: TContractState, new_class_hash: ClassHash);

    fn get_num_bets_in_market(
        self: @TContractState, user: ContractAddress, market_id: u256, market_type: u8
    ) -> u8;

    fn get_outcome_and_bet(
        self: @TContractState, user: ContractAddress, market_id: u256, market_type: u8, bet_num: u8
    ) -> UserBet;

    fn get_user_total_claimable(self: @TContractState, user: ContractAddress) -> u256;

    fn toggle_market(ref self: TContractState, market_id: u256, market_type: u8);

    fn settle_crypto_market(ref self: TContractState, market_id: u256);

    fn add_admin(ref self: TContractState, admin: ContractAddress);

    fn remove_all_markets(ref self: TContractState);

    fn get_user_crypto_markets(self: @TContractState, user: ContractAddress) -> Array<CryptoMarket>;

    fn get_user_sports_markets(self: @TContractState, user: ContractAddress) -> Array<SportsMarket>;
}

#[starknet::contract]
pub mod MarketFactory {
    use openzeppelin::token::erc20::interface::IERC20DispatcherTrait;
    use core::box::BoxTrait;
    use core::option::OptionTrait;
    use core::array::ArrayTrait;
    use super::{Market, Outcome, UserPosition, UserBet, CryptoMarket, SportsMarket};
    use starknet::{
        ContractAddress, ClassHash, get_caller_address, get_contract_address,
        contract_address_const, get_block_timestamp
    };
    use core::num::traits::zero::Zero;
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;
    use starknet::SyscallResultTrait;
    use pragma_lib::abi::{IPragmaABIDispatcher, IPragmaABIDispatcherTrait};
    use pragma_lib::types::{AggregationMode, DataType, PragmaPricesResponse};
    const one: u256 = 1_000_000_000_000_000_000;
    const MAX_ITERATIONS: u16 = 25;
    const PLATFORM_FEE: u256 = 2;

    #[storage]
    struct Storage {
        user_bet: LegacyMap::<(ContractAddress, u256, u8, u8), UserBet>,
        num_bets: LegacyMap::<(ContractAddress, u256, u8), u8>,
        markets: LegacyMap::<u256, Market>,
        crypto_markets: LegacyMap::<u256, CryptoMarket>,
        crypto_idx: u256,
        sports_markets: LegacyMap::<u256, SportsMarket>,
        sports_idx: u256,
        idx: u256,
        owner: ContractAddress,
        treasury_wallet: ContractAddress,
        admins: LegacyMap::<u128, ContractAddress>,
        num_admins: u128,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MarketCreated: MarketCreated,
        CryptoMarketCreated: CryptoMarketCreated,
        ShareBought: ShareBought,
        SportsShareBought: SportsShareBought,
        CryptoShareBought: CryptoShareBought,
        MarketSettled: MarketSettled,
        SportsMarketSettled: SportsMarketSettled,
        CryptoMarketSettled: CryptoMarketSettled,
        MarketToggled: MarketToggled,
        WinningsClaimed: WinningsClaimed,
        SportsWinningsClaimed: SportsWinningsClaimed,
        CryptoWinningsClaimed: CryptoWinningsClaimed,
        Upgraded: Upgraded,
        SportsMarketCreated: SportsMarketCreated,
        SportsMarketToggled: SportsMarketToggled,
        CryptoMarketToggled: CryptoMarketToggled,
    }
    #[derive(Drop, PartialEq, starknet::Event)]
    pub struct Upgraded {
        pub class_hash: ClassHash
    }
    #[derive(Drop, starknet::Event)]
    struct MarketCreated {
        market: Market
    }

    #[derive(Drop, starknet::Event)]
    struct CryptoMarketCreated {
        market: CryptoMarket
    }

    #[derive(Drop, starknet::Event)]
    struct SportsMarketCreated {
        market: SportsMarket
    }

    #[derive(Drop, starknet::Event)]
    struct CryptoMarketSettled {
        market: CryptoMarket
    }

    #[derive(Drop, starknet::Event)]
    struct SportsMarketSettled {
        market: SportsMarket
    }

    #[derive(Drop, starknet::Event)]
    struct ShareBought {
        user: ContractAddress,
        market: Market,
        outcome: Outcome,
        amount: u256
    }
    #[derive(Drop, starknet::Event)]
    struct SportsShareBought {
        user: ContractAddress,
        market: SportsMarket,
        outcome: Outcome,
        amount: u256
    }
    #[derive(Drop, starknet::Event)]
    struct CryptoShareBought {
        user: ContractAddress,
        market: CryptoMarket,
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
    struct SportsMarketToggled {
        market: SportsMarket
    }
    #[derive(Drop, starknet::Event)]
    struct CryptoMarketToggled {
        market: CryptoMarket
    }
    #[derive(Drop, starknet::Event)]
    struct WinningsClaimed {
        user: ContractAddress,
        market: Market,
        outcome: Outcome,
        amount: u256
    }
    #[derive(Drop, starknet::Event)]
    struct SportsWinningsClaimed {
        user: ContractAddress,
        market: SportsMarket,
        outcome: Outcome,
        amount: u256
    }
    #[derive(Drop, starknet::Event)]
    struct CryptoWinningsClaimed {
        user: ContractAddress,
        market: CryptoMarket,
        outcome: Outcome,
        amount: u256
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
    }

    fn create_share_tokens(names: (felt252, felt252)) -> (Outcome, Outcome) {
        let (name1, name2) = names;
        let mut token1 = Outcome { name: name1, bought_shares: 0 };
        let mut token2 = Outcome { name: name2, bought_shares: 0 };

        let tokens = (token1, token2);

        return tokens;
    }

    #[abi(embed_v0)]
    impl MarketFactory of super::IMarketFactory<ContractState> {
        fn create_market(
            ref self: ContractState,
            name: ByteArray,
            description: ByteArray,
            outcomes: (felt252, felt252),
            category: felt252,
            image: ByteArray,
            deadline: u64,
        ) {
            let mut i = 1;
            loop {
                if i > self.num_admins.read() {
                    panic!("Only admins can create markets.");
                }
                if self.admins.read(i) == get_caller_address() {
                    break;
                }
                i += 1;
            };
            let outcomes = create_share_tokens(outcomes);
            let market = Market {
                name,
                description,
                outcomes,
                is_settled: false,
                is_active: true,
                winning_outcome: Option::None,
                money_in_pool: 0,
                category,
                image,
                deadline,
                market_id: self.idx.read() + 1,
            };
            self.idx.write(self.idx.read() + 1);
            self.markets.write(self.idx.read(), market);
            let current_market = self.markets.read(self.idx.read());
            self.emit(MarketCreated { market: current_market });
        }
        fn create_crypto_market(
            ref self: ContractState,
            name: ByteArray,
            description: ByteArray,
            outcomes: (felt252, felt252),
            category: felt252,
            image: ByteArray,
            deadline: u64,
            conditions: u8,
            price_key: felt252,
            amount: u128,
        ) {
            let mut i = 1;
            loop {
                if i > self.num_admins.read() {
                    panic!("Only admins can create markets.");
                }
                if self.admins.read(i) == get_caller_address() {
                    break;
                }
                i += 1;
            };
            let outcomes = create_share_tokens(outcomes);
            let crypto_market = CryptoMarket {
                name,
                description,
                outcomes,
                is_settled: false,
                is_active: true,
                winning_outcome: Option::None,
                money_in_pool: 0,
                category,
                image,
                deadline,
                market_id: self.crypto_idx.read() + 1,
                conditions,
                price_key,
                amount,
            };
            self.crypto_idx.write(self.crypto_idx.read() + 1);
            self.crypto_markets.write(self.crypto_idx.read(), crypto_market);
            let current_market = self.crypto_markets.read(self.crypto_idx.read());
            self.emit(CryptoMarketCreated { market: current_market });
        }


        fn get_market(self: @ContractState, market_id: u256) -> Market {
            return self.markets.read(market_id);
        }

        fn create_sports_market(
            ref self: ContractState,
            name: ByteArray,
            description: ByteArray,
            outcomes: (felt252, felt252),
            category: felt252,
            image: ByteArray,
            deadline: u64,
            api_event_id: u64,
            is_home: bool,
        ) {
            let mut i = 1;
            loop {
                if i > self.num_admins.read() {
                    panic!("Only admins can create markets.");
                }
                if self.admins.read(i) == get_caller_address() {
                    break;
                }
                i += 1;
            };
            let outcomes = create_share_tokens(outcomes);
            let sports_market = SportsMarket {
                name,
                description,
                outcomes,
                is_settled: false,
                is_active: true,
                winning_outcome: Option::None,
                money_in_pool: 0,
                category,
                image,
                deadline,
                market_id: self.sports_idx.read() + 1,
                api_event_id,
                is_home,
            };
            self.sports_idx.write(self.sports_idx.read() + 1);
            self.sports_markets.write(self.sports_idx.read(), sports_market);
            let current_market = self.sports_markets.read(self.sports_idx.read());
            self.emit(SportsMarketCreated { market: current_market });
        }

        fn get_market_count(self: @ContractState) -> u256 {
            return self.idx.read();
        }

        fn settle_sports_market(ref self: ContractState, market_id: u256, winning_outcome: u8) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can settle markets.');
            assert(market_id <= self.sports_idx.read(), 'Market does not exist');
            let mut sports_market = self.sports_markets.read(market_id);
            assert(get_block_timestamp() > sports_market.deadline, 'Market has not expired.');
            sports_market.is_settled = true;
            sports_market.is_active = false;
            let (outcome1, outcome2) = sports_market.outcomes;
            if winning_outcome == 0 {
                sports_market.winning_outcome = Option::Some(outcome1);
            } else {
                sports_market.winning_outcome = Option::Some(outcome2);
            }
            self.sports_markets.write(market_id, sports_market);
            let current_market = self.sports_markets.read(market_id);
            self.emit(SportsMarketSettled { market: current_market });
        }

        fn get_crypto_market(self: @ContractState, market_id: u256) -> CryptoMarket {
            return self.crypto_markets.read(market_id);
        }

        fn get_all_crypto_markets(self: @ContractState) -> Array<CryptoMarket> {
            let mut markets: Array<CryptoMarket> = ArrayTrait::new();
            let mut i: u256 = 1;
            loop {
                if i > self.crypto_idx.read() {
                    break;
                }
                if self.crypto_markets.read(i).is_active == true {
                    markets.append(self.crypto_markets.read(i));
                }
                i += 1;
            };
            markets
        }

        fn get_sports_market(self: @ContractState, market_id: u256) -> SportsMarket {
            return self.sports_markets.read(market_id);
        }

        fn get_all_sports_markets(self: @ContractState) -> Array<SportsMarket> {
            let mut markets: Array<SportsMarket> = ArrayTrait::new();
            let mut i: u256 = 1;
            loop {
                if i > self.sports_idx.read() {
                    break;
                }
                if self.sports_markets.read(i).is_active == true {
                    markets.append(self.sports_markets.read(i));
                }
                i += 1;
            };
            markets
        }

        fn get_user_markets(self: @ContractState, user: ContractAddress) -> Array<Market> {
            let mut markets: Array<Market> = ArrayTrait::new();
            let mut i: u256 = 1;
            loop {
                if i > self.idx.read() {
                    break;
                }
                let total_bets = self.num_bets.read((user, i, 2));
                if total_bets > 0 {
                    markets.append(self.markets.read(i));
                }
                i += 1;
            };
            markets
        }

        fn get_user_crypto_markets(
            self: @ContractState, user: ContractAddress
        ) -> Array<CryptoMarket> {
            let mut markets: Array<CryptoMarket> = ArrayTrait::new();
            let mut i: u256 = 1;
            loop {
                if i > self.crypto_idx.read() {
                    break;
                }
                let total_bets = self.num_bets.read((user, i, 1));
                if total_bets > 0 {
                    markets.append(self.crypto_markets.read(i));
                }
                i += 1;
            };
            markets
        }

        fn get_user_sports_markets(
            self: @ContractState, user: ContractAddress
        ) -> Array<SportsMarket> {
            let mut markets: Array<SportsMarket> = ArrayTrait::new();
            let mut i: u256 = 1;
            loop {
                if i > self.sports_idx.read() {
                    break;
                }
                let total_bets = self.num_bets.read((user, i, 0));
                if total_bets > 0 {
                    markets.append(self.sports_markets.read(i));
                };
                i += 1;
            };
            markets
        }

        fn get_num_bets_in_market(
            self: @ContractState, user: ContractAddress, market_id: u256, market_type: u8
        ) -> u8 {
            return self.num_bets.read((user, market_id, market_type));
        }

        fn settle_crypto_market(ref self: ContractState, market_id: u256) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can settle markets.');
            assert(market_id <= self.crypto_idx.read(), 'Market does not exist');
            let mut crypto_market = self.crypto_markets.read(market_id);
            let price = get_asset_price_median(DataType::SpotEntry(crypto_market.price_key));
            crypto_market.is_settled = true;
            crypto_market.is_active = false;
            let (outcome1, outcome2) = crypto_market.outcomes;
            if crypto_market.conditions == 0 {
                if price < crypto_market.amount {
                    crypto_market.winning_outcome = Option::Some(outcome1);
                } else {
                    crypto_market.winning_outcome = Option::Some(outcome2);
                }
            } else {
                if price > crypto_market.amount {
                    crypto_market.winning_outcome = Option::Some(outcome1);
                } else {
                    crypto_market.winning_outcome = Option::Some(outcome2);
                }
            }
            self.crypto_markets.write(market_id, crypto_market);
            let current_market = self.crypto_markets.read(market_id);
            self.emit(CryptoMarketSettled { market: current_market });
        }

        fn toggle_market(ref self: ContractState, market_id: u256, market_type: u8) {
            let mut i = 1;
            loop {
                if i > self.num_admins.read() {
                    panic!("Only admins can create markets.");
                }
                if self.admins.read(i) == get_caller_address() {
                    break;
                }
                i += 1;
            };
            if market_type == 0 {
                let mut market = self.sports_markets.read(market_id);
                market.is_active = !market.is_active;
                self.sports_markets.write(market_id, market);
                let current_market = self.sports_markets.read(market_id);
                self.emit(SportsMarketToggled { market: current_market });
            } else if market_type == 1 {
                let mut market = self.crypto_markets.read(market_id);
                market.is_active = !market.is_active;
                self.crypto_markets.write(market_id, market);
                let current_market = self.crypto_markets.read(market_id);
                self.emit(CryptoMarketToggled { market: current_market });
            } else {
                let mut market = self.markets.read(market_id);
                market.is_active = !market.is_active;
                self.markets.write(market_id, market);
                let current_market = self.markets.read(market_id);
                self.emit(MarketToggled { market: current_market });
            }
        }

        fn get_outcome_and_bet(
            self: @ContractState,
            user: ContractAddress,
            market_id: u256,
            market_type: u8,
            bet_num: u8
        ) -> UserBet {
            let user_bet = self.user_bet.read((user, market_id, market_type, bet_num));
            return user_bet;
        }

        fn add_admin(ref self: ContractState, admin: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can add admins.');
            self.num_admins.write(self.num_admins.read() + 1);
            self.admins.write(self.num_admins.read(), admin);
        }

        fn get_user_total_claimable(self: @ContractState, user: ContractAddress) -> u256 {
            let mut total: u256 = 0;
            let mut i: u256 = 1;
            loop {
                if i > self.idx.read() {
                    break;
                }
                let market = self.sports_markets.read(i);
                if market.is_settled == false {
                    i += 1;
                    continue;
                }
                let total_bets = self.num_bets.read((user, i, 0));

                if total_bets > 0 {
                    let mut bet_num = 1;
                    loop {
                        if bet_num > total_bets {
                            break;
                        }
                        let user_bet = self.user_bet.read((user, i, 0, bet_num));
                        if user_bet.outcome == market.winning_outcome.unwrap() {
                            if user_bet.position.has_claimed == false {
                                total += user_bet.position.amount
                                    * market.money_in_pool
                                    / user_bet.outcome.bought_shares;
                            }
                        }
                    }
                }
                i += 1;
            };
            let mut i: u256 = 1;
            loop {
                if i > self.idx.read() {
                    break;
                }
                let market = self.crypto_markets.read(i);
                if market.is_settled == false {
                    i += 1;
                    continue;
                }
                let total_bets = self.num_bets.read((user, i, 1));

                if total_bets > 0 {
                    let mut bet_num = 1;
                    loop {
                        if bet_num > total_bets {
                            break;
                        }
                        let user_bet = self.user_bet.read((user, i, 1, bet_num));
                        if user_bet.outcome == market.winning_outcome.unwrap() {
                            if user_bet.position.has_claimed == false {
                                total += user_bet.position.amount
                                    * market.money_in_pool
                                    / user_bet.outcome.bought_shares;
                            }
                        }
                    }
                }
                i += 1;
            };
            let mut i: u256 = 1;
            loop {
                if i > self.idx.read() {
                    break;
                }
                let market = self.markets.read(i);
                if market.is_settled == false {
                    i += 1;
                    continue;
                }
                let total_bets = self.num_bets.read((user, i, 2));

                if total_bets > 0 {
                    let mut bet_num = 1;
                    loop {
                        if bet_num > total_bets {
                            break;
                        }
                        let user_bet = self.user_bet.read((user, i, 2, bet_num));
                        if user_bet.outcome == market.winning_outcome.unwrap() {
                            if user_bet.position.has_claimed == false {
                                total += user_bet.position.amount
                                    * market.money_in_pool
                                    / user_bet.outcome.bought_shares;
                            }
                        }
                    }
                }
                i += 1;
            };
            total
        }

        // creates a position in a market for a user
        fn buy_shares(
            ref self: ContractState,
            market_id: u256,
            token_to_mint: u8,
            amount: u256,
            market_type: u8
        ) -> bool {
            let usdc_address = contract_address_const::<
                0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7
            >();
            let dispatcher = IERC20Dispatcher { contract_address: usdc_address };

            match market_type {
                0 => {
                    let mut market = self.sports_markets.read(market_id);
                    assert(market.is_active, 'Market not active.');
                    assert(get_block_timestamp() < market.deadline, 'Market has expired.');
                    let (mut outcome1, mut outcome2) = market.outcomes;

                    let txn: bool = dispatcher
                        .transfer_from(get_caller_address(), get_contract_address(), amount);
                    dispatcher.transfer(self.treasury_wallet.read(), amount * PLATFORM_FEE / 100);

                    let bought_shares = amount - amount * PLATFORM_FEE / 100;
                    let money_in_pool = market.money_in_pool + bought_shares;

                    if token_to_mint == 0 {
                        outcome1.bought_shares += bought_shares;
                    } else {
                        outcome2.bought_shares += bought_shares;
                    }

                    market.outcomes = (outcome1, outcome2);
                    market.money_in_pool = money_in_pool;

                    self.sports_markets.write(market_id, market);
                    self
                        .num_bets
                        .write(
                            (get_caller_address(), market_id, 0),
                            self.num_bets.read((get_caller_address(), market_id, 0)) + 1
                        );
                    self
                        .user_bet
                        .write(
                            (
                                get_caller_address(),
                                market_id,
                                market_type,
                                self.num_bets.read((get_caller_address(), market_id, 0))
                            ),
                            UserBet {
                                outcome: if token_to_mint == 0 {
                                    outcome1
                                } else {
                                    outcome2
                                },
                                position: UserPosition { amount: amount, has_claimed: false }
                            }
                        );
                    let new_market = self.sports_markets.read(market_id);
                    self
                        .emit(
                            SportsShareBought {
                                user: get_caller_address(),
                                market: new_market,
                                outcome: if token_to_mint == 0 {
                                    outcome1
                                } else {
                                    outcome2
                                },
                                amount: amount
                            }
                        );
                    txn
                },
                1 => {
                    let mut market = self.crypto_markets.read(market_id);
                    assert(market.is_active, 'Market is not active.');
                    assert(get_block_timestamp() < market.deadline, 'Market has expired.');
                    let (mut outcome1, mut outcome2) = market.outcomes;

                    let txn: bool = dispatcher
                        .transfer_from(get_caller_address(), get_contract_address(), amount);
                    dispatcher.transfer(self.treasury_wallet.read(), amount * PLATFORM_FEE / 100);

                    let bought_shares = amount - amount * PLATFORM_FEE / 100;
                    let money_in_pool = market.money_in_pool + bought_shares;

                    if token_to_mint == 0 {
                        outcome1.bought_shares += bought_shares;
                    } else {
                        outcome2.bought_shares += bought_shares;
                    }

                    market.outcomes = (outcome1, outcome2);
                    market.money_in_pool = money_in_pool;

                    self.crypto_markets.write(market_id, market);
                    self
                        .num_bets
                        .write(
                            (get_caller_address(), market_id, 1),
                            self.num_bets.read((get_caller_address(), market_id, 1)) + 1
                        );
                    self
                        .user_bet
                        .write(
                            (
                                get_caller_address(),
                                market_id,
                                market_type,
                                self.num_bets.read((get_caller_address(), market_id, 1))
                            ),
                            UserBet {
                                outcome: if token_to_mint == 0 {
                                    outcome1
                                } else {
                                    outcome2
                                },
                                position: UserPosition { amount: amount, has_claimed: false }
                            }
                        );
                    let new_market = self.crypto_markets.read(market_id);
                    self
                        .emit(
                            CryptoShareBought {
                                user: get_caller_address(),
                                market: new_market,
                                outcome: if token_to_mint == 0 {
                                    outcome1
                                } else {
                                    outcome2
                                },
                                amount: amount
                            }
                        );
                    txn
                },
                2 => {
                    let mut market = self.markets.read(market_id);
                    assert(market.is_active, 'Market is not active.');
                    assert(get_block_timestamp() < market.deadline, 'Market has expired.');
                    let (mut outcome1, mut outcome2) = market.outcomes;

                    let txn: bool = dispatcher
                        .transfer_from(get_caller_address(), get_contract_address(), amount);
                    dispatcher.transfer(self.treasury_wallet.read(), amount * PLATFORM_FEE / 100);

                    let bought_shares = amount - amount * PLATFORM_FEE / 100;
                    let money_in_pool = market.money_in_pool + bought_shares;

                    if token_to_mint == 0 {
                        outcome1.bought_shares += bought_shares;
                    } else {
                        outcome2.bought_shares += bought_shares;
                    }

                    market.outcomes = (outcome1, outcome2);
                    market.money_in_pool = money_in_pool;

                    self.markets.write(market_id, market);
                    self
                        .num_bets
                        .write(
                            (get_caller_address(), market_id, 2),
                            self.num_bets.read((get_caller_address(), market_id, 2)) + 1
                        );
                    self
                        .user_bet
                        .write(
                            (
                                get_caller_address(),
                                market_id,
                                market_type,
                                self.num_bets.read((get_caller_address(), market_id, 2))
                            ),
                            UserBet {
                                outcome: if token_to_mint == 0 {
                                    outcome1
                                } else {
                                    outcome2
                                },
                                position: UserPosition { amount: amount, has_claimed: false }
                            }
                        );
                    let new_market = self.markets.read(market_id);
                    self
                        .emit(
                            ShareBought {
                                user: get_caller_address(),
                                market: new_market,
                                outcome: if token_to_mint == 0 {
                                    outcome1
                                } else {
                                    outcome2
                                },
                                amount: amount
                            }
                        );
                    txn
                },
                _ => panic!("Invalid market type"),
            }
        }


        fn remove_all_markets(ref self: ContractState) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can remove markets.');
            self.idx.write(0);
        }

        fn get_treasury_wallet(self: @ContractState) -> ContractAddress {
            assert(get_caller_address() == self.owner.read(), 'Only owner can read.');
            return self.treasury_wallet.read();
        }

        fn claim_winnings(ref self: ContractState, market_id: u256, market_type: u8, bet_num: u8) {
            if (market_type == 0) {
                assert(market_id <= self.sports_idx.read(), 'Market does not exist');
                let mut winnings = 0;
                let market = self.sports_markets.read(market_id);
                assert(market.is_settled == true, 'Market not settled');
                let total_bets = self.num_bets.read((get_caller_address(), market_id, market_type));
                if total_bets == 0 {
                    panic!("User has no bets in this market.");
                }
                let user_bet: UserBet = self
                    .user_bet
                    .read((get_caller_address(), market_id, market_type, bet_num));
                assert(user_bet.position.has_claimed == false, 'User has claimed winnings.');
                let winning_outcome = market.winning_outcome.unwrap();
                assert(user_bet.outcome == winning_outcome, 'User did not win!');
                winnings = user_bet.position.amount
                    * market.money_in_pool
                    / user_bet.outcome.bought_shares;
                let usdc_address = contract_address_const::<
                    0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7
                >();
                let dispatcher = IERC20Dispatcher { contract_address: usdc_address };
                dispatcher.transfer(get_caller_address(), winnings);
                self
                    .user_bet
                    .write(
                        (get_caller_address(), market_id, market_type, bet_num),
                        UserBet {
                            outcome: user_bet.outcome,
                            position: UserPosition {
                                amount: user_bet.position.amount, has_claimed: true
                            }
                        }
                    );
                self
                    .emit(
                        SportsWinningsClaimed {
                            user: get_caller_address(),
                            market: market,
                            outcome: user_bet.outcome,
                            amount: winnings
                        }
                    );
            } else if (market_type == 1) {
                assert(market_id <= self.crypto_idx.read(), 'Market does not exist');
                let market = self.crypto_markets.read(market_id);
                assert(market.is_settled == true, 'Market not settled');
                let total_bets = self.num_bets.read((get_caller_address(), market_id, market_type));
                if total_bets == 0 {
                    panic!("User has no bets in this market.");
                }
                let user_bet: UserBet = self
                    .user_bet
                    .read((get_caller_address(), market_id, market_type, bet_num));
                assert(user_bet.position.has_claimed == false, 'User has claimed winnings.');
                let mut winnings = 0;
                let winning_outcome = market.winning_outcome.unwrap();
                assert(user_bet.outcome == winning_outcome, 'User did not win!');
                winnings = user_bet.position.amount
                    * market.money_in_pool
                    / user_bet.outcome.bought_shares;
                let usdc_address = contract_address_const::<
                    0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7
                >();
                let dispatcher = IERC20Dispatcher { contract_address: usdc_address };
                dispatcher.transfer(get_caller_address(), winnings);
                self
                    .user_bet
                    .write(
                        (get_caller_address(), market_id, market_type, bet_num),
                        UserBet {
                            outcome: user_bet.outcome,
                            position: UserPosition {
                                amount: user_bet.position.amount, has_claimed: true
                            }
                        }
                    );
                self
                    .emit(
                        CryptoWinningsClaimed {
                            user: get_caller_address(),
                            market: market,
                            outcome: user_bet.outcome,
                            amount: winnings
                        }
                    );
            } else {
                assert(market_id <= self.idx.read(), 'Market does not exist');
                let market = self.markets.read(market_id);
                assert(market.is_settled == true, 'Market not settled');
                let total_bets = self.num_bets.read((get_caller_address(), market_id, market_type));
                if total_bets == 0 {
                    panic!("User has no bets in this market.");
                }
                let user_bet: UserBet = self
                    .user_bet
                    .read((get_caller_address(), market_id, market_type, bet_num));
                assert(user_bet.position.has_claimed == false, 'User has claimed winnings.');
                let mut winnings = 0;
                let winning_outcome = market.winning_outcome.unwrap();
                assert(user_bet.outcome == winning_outcome, 'User did not win!');
                winnings = user_bet.position.amount
                    * market.money_in_pool
                    / user_bet.outcome.bought_shares;
                let usdc_address = contract_address_const::<
                    0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7
                >();
                let dispatcher = IERC20Dispatcher { contract_address: usdc_address };
                dispatcher.transfer(get_caller_address(), winnings);
                self
                    .user_bet
                    .write(
                        (get_caller_address(), market_id, market_type, bet_num),
                        UserBet {
                            outcome: user_bet.outcome,
                            position: UserPosition {
                                amount: user_bet.position.amount, has_claimed: true
                            }
                        }
                    );
                self
                    .emit(
                        WinningsClaimed {
                            user: get_caller_address(),
                            market: market,
                            outcome: user_bet.outcome,
                            amount: winnings
                        }
                    );
            }
        }

        fn set_treasury_wallet(ref self: ContractState, wallet: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can set.');
            self.treasury_wallet.write(wallet);
        }

        fn settle_market(ref self: ContractState, market_id: u256, winning_outcome: u8) {
            let mut i = 1;
            loop {
                if i > self.num_admins.read() {
                    panic!("Only admins can create markets.");
                }
                if self.admins.read(i) == get_caller_address() {
                    break;
                }
                i += 1;
            };
            assert(market_id <= self.idx.read(), 'Market does not exist');
            let mut market = self.markets.read(market_id);
            market.is_settled = true;
            market.is_active = false;
            let (outcome1, outcome2) = market.outcomes;
            if winning_outcome == 0 {
                market.winning_outcome = Option::Some(outcome1);
            } else {
                market.winning_outcome = Option::Some(outcome2);
            }
            self.markets.write(market_id, market);
            let current_market = self.markets.read(market_id);
            self.emit(MarketSettled { market: current_market });
        }

        fn settle_crypto_market_manually(
            ref self: ContractState, market_id: u256, winning_outcome: u8
        ) {
            let mut i = 1;
            loop {
                if i > self.num_admins.read() {
                    panic!("Only admins can create markets.");
                }
                if self.admins.read(i) == get_caller_address() {
                    break;
                }
                i += 1;
            };
            assert(market_id <= self.crypto_idx.read(), 'Market does not exist');
            let mut market = self.crypto_markets.read(market_id);
            market.is_settled = true;
            market.is_active = false;
            let (outcome1, outcome2) = market.outcomes;
            if winning_outcome == 0 {
                market.winning_outcome = Option::Some(outcome1);
            } else {
                market.winning_outcome = Option::Some(outcome2);
            }
            self.crypto_markets.write(market_id, market);
            let current_market = self.crypto_markets.read(market_id);
            self.emit(CryptoMarketSettled { market: current_market });
        }

        fn settle_sports_market_manually(
            ref self: ContractState, market_id: u256, winning_outcome: u8
        ) {
            let mut i = 1;
            loop {
                if i > self.num_admins.read() {
                    panic!("Only admins can create markets.");
                }
                if self.admins.read(i) == get_caller_address() {
                    break;
                }
                i += 1;
            };
            assert(market_id <= self.sports_idx.read(), 'Market does not exist');
            let mut market = self.sports_markets.read(market_id);
            market.is_settled = true;
            market.is_active = false;
            let (outcome1, outcome2) = market.outcomes;
            if winning_outcome == 0 {
                market.winning_outcome = Option::Some(outcome1);
            } else {
                market.winning_outcome = Option::Some(outcome2);
            }
            self.sports_markets.write(market_id, market);
            let current_market = self.sports_markets.read(market_id);
            self.emit(SportsMarketSettled { market: current_market });
        }

        fn get_all_markets(self: @ContractState) -> Array<Market> {
            let mut markets: Array<Market> = ArrayTrait::new();
            let mut i: u256 = 1;
            loop {
                if i > self.idx.read() {
                    break;
                }
                if self.markets.read(i).is_active == true {
                    markets.append(self.markets.read(i));
                }
                i += 1;
            };
            markets
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            return self.owner.read();
        }

        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            assert(get_caller_address() == self.owner.read(), 'Only owner can upgrade.');
            starknet::syscalls::replace_class_syscall(new_class_hash).unwrap_syscall();
            self.emit(Upgraded { class_hash: new_class_hash });
        }
    }


    fn get_asset_price_median(asset: DataType) -> u128 {
        let oracle_address: ContractAddress = contract_address_const::<
            0x2a85bd616f912537c50a49a4076db02c00b29b2cdc8a197ce92ed1837fa875b
        >();
        let oracle_dispatcher = IPragmaABIDispatcher { contract_address: oracle_address };
        let output: PragmaPricesResponse = oracle_dispatcher
            .get_data(asset, AggregationMode::Median(()));
        return output.price;
    }
}
