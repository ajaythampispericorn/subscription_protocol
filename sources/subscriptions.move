module subscription::subscriptions {
    use std::signer;
    use std::string::String;
    use std::vector;
    use std::account;
    use std::option::{Self, Option};
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_std::table::{Self, Table};

    use subscription::registry;
    use subscription::plans::{Self, PlanRegistry};
    use subscription::time;

    const STATUS_ACTIVE: u8 = 0;
    const STATUS_CANCELLED: u8 = 1;
    const STATUS_EXPIRED: u8 = 2;

    const ERR_NOT_AUTHORIZED: u64 = 1;
    const ERR_SUBSCRIPTION_NOT_FOUND: u64 = 2;
    const ERR_SUBSCRIPTION_ALREADY_CANCELLED: u64 = 3;
    const ERR_SUBSCRIPTION_INACTIVE: u64 = 4;
    const ERR_INSUFFICIENT_PAYMENT: u64 = 5;
    const ERR_EXPIRED_SUBSCRIPTION: u64 = 6;
    const ERR_SUBSCRIPTION_ACTIVE: u64 = 7;

    struct UserSubscription has key, store {
        id: u64,
        subscriber: address,
        plan_id: u64,
        creator: address,
        start_time: u64,
        end_time: u64,
        status: u8,
        payment_amount: u64,
        previous_subscription_id: Option<u64>,
    }

    struct UserSubscriptionHistory has key {
        active_subscriptions: vector<u64>,
        past_subscriptions: vector<u64>
    }

    struct SubscriptionStore has key {
        subscriptions: Table<u64, UserSubscription>,
        user_subscriptions: Table<address, vector<u64>>,
        creator_subscribers: Table<address, vector<address>>,
        subscription_create_event:event::EventHandle<SubscriptionCreatedEvent>,
        subscription_cancel_event:event::EventHandle<SubscriptionCancelEvent>,
        subscription_expire_event:event::EventHandle<SubscriptionExpiredEvent>,
        subscription_renew_event:event::EventHandle<SubscriptionRenewedEvent>
    }

    struct SubscriptionCreatedEvent has drop, store {
        subscription_id: u64,
        subscriber: address,
        plan_id: u64,
        creator: address,
        start_time: u64,
        end_time: u64,
        payment_amount: u64
    }

    struct SubscriptionCancelEvent has drop, store {
        subscription_id: u64,
        subscriber: address,
        plan_id: u64,
        timestamp: u64
    }

    struct SubscriptionExpiredEvent has drop, store {
        subscription_id: u64,
        subscriber: address,
        plan_id: u64,
        timestamp: u64
    }

    struct SubscriptionRenewedEvent has drop, store {
        subscription_id: u64,
        subscriber: address,
        plan_id: u64,
        start_time: u64,
        end_time: u64,
        payment_amount: u64
    }

    public entry fun initialize_subscription_registry(admin: &signer) {
        assert!(signer::address_of(admin) == @subscription, ERR_NOT_AUTHORIZED);
        move_to(admin, SubscriptionStore {
            subscriptions: table::new(),
            user_subscriptions: table::new(),
            creator_subscribers: table::new(),
            subscription_create_event:account::new_event_handle<SubscriptionCreatedEvent>(admin),
            subscription_cancel_event:account::new_event_handle<SubscriptionCancelEvent>(admin),
            subscription_expire_event:account::new_event_handle<SubscriptionExpiredEvent>(admin),
            subscription_renew_event:account::new_event_handle<SubscriptionRenewedEvent>(admin),
        });
    }

    public entry fun subscribe(
        subscriber: &signer,
        plan_id: u64,
        payment_amount: u64
    ) acquires SubscriptionStore, UserSubscriptionHistory {
        let sub_registry = borrow_global_mut<SubscriptionStore>(@subscription);

        let subscriber_addr = signer::address_of(subscriber);
        plans::assert_plan_subscribable(plan_id);

        let (creator, _title, price, duration, _active) = plans::get_plan(plan_id);
        assert!(payment_amount >= price, ERR_INSUFFICIENT_PAYMENT);

        let current_time = timestamp::now_seconds();
        let end_time = time::calculate_end_time(current_time, duration);

        let platform_fee = (payment_amount * registry::get_platform_fee_percentage()) / 10000;
        let creator_payment = payment_amount - platform_fee;

        coin::transfer<AptosCoin>(subscriber, creator, creator_payment);
        coin::transfer<AptosCoin>(subscriber, @subscription, platform_fee);

        let subscription_id = registry::generate_subscription_id();
        let subscription = UserSubscription {
            id: subscription_id,
            subscriber: subscriber_addr,
            plan_id,
            creator,
            start_time: current_time,
            end_time,
            status: STATUS_ACTIVE,
            payment_amount,
            previous_subscription_id: option::none()
        };

        table::add(&mut sub_registry.subscriptions, subscription_id, subscription);

        if (!table::contains(&sub_registry.user_subscriptions, subscriber_addr)) {
            table::add(&mut sub_registry.user_subscriptions, subscriber_addr, vector::empty<u64>());
        };

        let user_subs = table::borrow_mut(&mut sub_registry.user_subscriptions, subscriber_addr);
        vector::push_back(user_subs, subscription_id);

        if (!table::contains(&sub_registry.creator_subscribers, creator)) {
            table::add(&mut sub_registry.creator_subscribers, creator, vector::empty<address>());
        };

        let creator_subs = table::borrow_mut(&mut sub_registry.creator_subscribers, creator);
        if (!vector::contains(creator_subs, &subscriber_addr)) {
            vector::push_back(creator_subs, subscriber_addr);
        };

        if (!exists<UserSubscriptionHistory>(subscriber_addr)) {
            move_to(subscriber, UserSubscriptionHistory {
                active_subscriptions: vector::empty(),
                past_subscriptions: vector::empty()
            });
        };

        let history = borrow_global_mut<UserSubscriptionHistory>(subscriber_addr);
        vector::push_back(&mut history.active_subscriptions, subscription_id);

        event::emit_event(&mut sub_registry.subscription_create_event,SubscriptionCreatedEvent {
            subscription_id,
            subscriber: subscriber_addr,
            plan_id,
            creator,
            start_time: current_time,
            end_time,
            payment_amount
        });
    }

    public entry fun cancel_subscription(
        subscriber: &signer,
        subscription_id: u64,
    ) acquires SubscriptionStore, UserSubscriptionHistory {
        let subscriber_addr = signer::address_of(subscriber);
        let sub_registry = borrow_global_mut<SubscriptionStore>(@subscription);
        
        assert!(table::contains(&sub_registry.subscriptions, subscription_id), 
            ERR_SUBSCRIPTION_NOT_FOUND);
        
        let sub = table::borrow_mut(&mut sub_registry.subscriptions, subscription_id);
        assert!(sub.subscriber == subscriber_addr, ERR_NOT_AUTHORIZED);
        assert!(sub.status == STATUS_ACTIVE, ERR_SUBSCRIPTION_ALREADY_CANCELLED);
        
        sub.status = STATUS_CANCELLED;
        sub.end_time = timestamp::now_seconds();
        
        let history = borrow_global_mut<UserSubscriptionHistory>(subscriber_addr);
        let (found, index) = vector::index_of(&history.active_subscriptions, &subscription_id);
        if (found) {
            vector::remove(&mut history.active_subscriptions, index);
            vector::push_back(&mut history.past_subscriptions, subscription_id);
        };
        
        registry::decrease_active_subscriptions();
        
        event::emit_event(&mut sub_registry.subscription_cancel_event, SubscriptionCancelEvent {
            subscription_id,
            subscriber: subscriber_addr,
            plan_id: sub.plan_id,
            timestamp: timestamp::now_seconds()
        });
    }

    public entry fun renew_subscription(
        subscriber: &signer,
        subscription_id: u64,
        payment_amount: u64
    ) acquires SubscriptionStore, UserSubscriptionHistory {
        let subscriber_addr = signer::address_of(subscriber);
        let sub_registry = borrow_global_mut<SubscriptionStore>(@subscription);
        
        assert!(table::contains(&sub_registry.subscriptions, subscription_id), 
            ERR_SUBSCRIPTION_NOT_FOUND);
        
        let sub = table::borrow_mut(&mut sub_registry.subscriptions, subscription_id);
        assert!(sub.subscriber == subscriber_addr, ERR_NOT_AUTHORIZED);
        
        if (sub.status == STATUS_ACTIVE) {
            assert!(time::is_subscription_expired(sub.end_time), 
                ERR_SUBSCRIPTION_ACTIVE);
        };
        
        let (creator, _title, price, duration, _active) = plans::get_plan(sub.plan_id);
        assert!(payment_amount >= price, ERR_INSUFFICIENT_PAYMENT);
        
        let current_time = timestamp::now_seconds();
        let end_time = time::calculate_end_time(current_time, duration);
        
        let platform_fee = (payment_amount * registry::get_platform_fee_percentage()) / 10000;
        let creator_payment = payment_amount - platform_fee;
        
        coin::transfer<AptosCoin>(subscriber, creator, creator_payment);
        coin::transfer<AptosCoin>(subscriber, @subscription, platform_fee);
        
        sub.start_time = current_time;
        sub.end_time = end_time;
        sub.status = STATUS_ACTIVE;
        sub.payment_amount = payment_amount;
        
        let history = borrow_global_mut<UserSubscriptionHistory>(subscriber_addr);
        if (!vector::contains(&history.active_subscriptions, &subscription_id)) {
            let (found, index) = vector::index_of(&history.past_subscriptions, &subscription_id);
            if (found) {
                vector::remove(&mut history.past_subscriptions, index);
            };
            vector::push_back(&mut history.active_subscriptions, subscription_id);
        };
        
        event::emit_event(&mut sub_registry.subscription_renew_event, SubscriptionRenewedEvent {
            subscription_id,
            subscriber: subscriber_addr,
            plan_id: sub.plan_id,
            start_time: current_time,
            end_time,
            payment_amount
        });
    }

    public entry fun upgrade_subscription(
        subscriber: &signer,
        current_subscription_id: u64,
        new_plan_id: u64,
        additional_payment: u64
    ) acquires SubscriptionStore, UserSubscriptionHistory {
        let subscriber_addr = signer::address_of(subscriber);
        let sub_registry = borrow_global_mut<SubscriptionStore>(@subscription);
        
        assert!(table::contains(&sub_registry.subscriptions, current_subscription_id), 
            ERR_SUBSCRIPTION_NOT_FOUND);
        
        let current_sub = table::borrow(&sub_registry.subscriptions, current_subscription_id);
        assert!(current_sub.subscriber == subscriber_addr, ERR_NOT_AUTHORIZED);
        assert!(current_sub.status == STATUS_ACTIVE, ERR_SUBSCRIPTION_INACTIVE);
        assert!(!time::is_subscription_expired(current_sub.end_time), 
            ERR_EXPIRED_SUBSCRIPTION);
        
        plans::assert_plan_subscribable(new_plan_id);
        let (creator, _title, price, duration, _active) = plans::get_plan(new_plan_id);
        
        let current_time = timestamp::now_seconds();
        let remaining_time = current_sub.end_time - current_time;
        let total_duration = current_sub.end_time - current_sub.start_time;
        
        let remaining_value = time::calculate_remaining_value(
            current_sub.payment_amount,
            total_duration,
            remaining_time
        );
        
        let required_payment = if (remaining_value >= price) {
            0
        } else {
            price - remaining_value
        };
        
        assert!(additional_payment >= required_payment, ERR_INSUFFICIENT_PAYMENT);
        
        if (required_payment > 0) {
            let platform_fee = (additional_payment * registry::get_platform_fee_percentage()) / 10000;
            let creator_payment = additional_payment - platform_fee;
            coin::transfer<AptosCoin>(subscriber, creator, creator_payment);
            coin::transfer<AptosCoin>(subscriber, @subscription, platform_fee);
        };
        
        let prorated_duration = time::calculate_prorated_duration(
            remaining_value,
            price,
            duration
        );
        
        let new_end_time = time::calculate_end_time(current_time, duration + prorated_duration);
        
        // Capture plan_id before dropping the mutable borrow
        let plan_id;
        {
            let current_sub = table::borrow_mut(&mut sub_registry.subscriptions, current_subscription_id);
            plan_id = current_sub.plan_id;
            current_sub.status = STATUS_CANCELLED;
        }; // current_sub is dropped here

        let new_subscription_id = registry::generate_subscription_id();
        let new_subscription = UserSubscription {
            id: new_subscription_id,
            subscriber: subscriber_addr,
            plan_id: new_plan_id,
            creator,
            start_time: current_time,
            end_time: new_end_time,
            status: STATUS_ACTIVE,
            payment_amount: price,
            previous_subscription_id: option::some(current_subscription_id),
        };
        
        table::add(&mut sub_registry.subscriptions, new_subscription_id, new_subscription);
        
        let user_subs = table::borrow_mut(&mut sub_registry.user_subscriptions, subscriber_addr);
        vector::push_back(user_subs, new_subscription_id);
        
        let history = borrow_global_mut<UserSubscriptionHistory>(subscriber_addr);
        let (found, index) = vector::index_of(&history.active_subscriptions, &current_subscription_id);
        if (found) {
            vector::remove(&mut history.active_subscriptions, index);
            vector::push_back(&mut history.past_subscriptions, current_subscription_id);
        };
        vector::push_back(&mut history.active_subscriptions, new_subscription_id);
        
        event::emit_event(&mut sub_registry.subscription_cancel_event, SubscriptionCancelEvent {
            subscription_id: current_subscription_id,
            subscriber: subscriber_addr,
            plan_id,
            timestamp: current_time,
        });
        
        event::emit_event(&mut sub_registry.subscription_create_event, SubscriptionCreatedEvent {
            subscription_id: new_subscription_id,
            subscriber: subscriber_addr,
            plan_id: new_plan_id,
            creator,
            start_time: current_time,
            end_time: new_end_time,
            payment_amount: price,
        });
    }

    public fun has_active_subscription(user: address, creator: address): bool acquires SubscriptionStore {
        let sub_registry = borrow_global<SubscriptionStore>(@subscription);
        
        if (!table::contains(&sub_registry.user_subscriptions, user)) {
            return false
        };
        
        let user_subscription_ids = table::borrow(&sub_registry.user_subscriptions, user);
        let len = vector::length(user_subscription_ids);
        let i = 0;
        
        while (i < len) {
            let subscription_id = *vector::borrow(user_subscription_ids, i);
            if (table::contains(&sub_registry.subscriptions, subscription_id)) {
                let sub = table::borrow(&sub_registry.subscriptions, subscription_id);
                if (sub.creator == creator && sub.status == STATUS_ACTIVE &&
                    !time::is_subscription_expired(sub.end_time)) {
                    return true
                };
            };
            i = i + 1;
        };
        false
    }

    public fun get_subscription(subscription_id: u64): (address, u64, address, u64, u64, u8) acquires SubscriptionStore {
        let sub_registry = borrow_global<SubscriptionStore>(@subscription);
        assert!(table::contains(&sub_registry.subscriptions, subscription_id), 
            ERR_SUBSCRIPTION_NOT_FOUND);
        
        let sub = table::borrow(&sub_registry.subscriptions, subscription_id);
        (
            sub.subscriber,
            sub.plan_id,
            sub.creator,
            sub.start_time,
            sub.end_time,
            sub.status
        )
    }

    public fun get_active_subscriptions(user: address): vector<u64> acquires UserSubscriptionHistory {
        // Instead of returning a reference, return a copy
        if (!exists<UserSubscriptionHistory>(user)) {
            return vector::empty<u64>()
        };
        
        let history = borrow_global<UserSubscriptionHistory>(user);
        *&history.active_subscriptions // Return a copy
    }

    public fun get_past_subscriptions(user: address): vector<u64> acquires UserSubscriptionHistory {
        // Instead of returning a reference, return a copy
        if (!exists<UserSubscriptionHistory>(user)) {
            return vector::empty<u64>()
        };
        
        let history = borrow_global<UserSubscriptionHistory>(user);
        *&history.past_subscriptions // Return a copy
    }

    public fun user_has_history(user: address): bool {
        exists<UserSubscriptionHistory>(user)
    }

    public fun get_subscription_status(subscription_id: u64): u8 acquires SubscriptionStore {
        let store = borrow_global<SubscriptionStore>(@subscription);
        assert!(table::contains(&store.subscriptions, subscription_id), 
            ERR_SUBSCRIPTION_NOT_FOUND);
        let sub = table::borrow(&store.subscriptions, subscription_id);
        sub.status
    }

    public fun get_subscription_end_time(subscription_id: u64): u64 acquires SubscriptionStore {
        let store = borrow_global<SubscriptionStore>(@subscription);
        assert!(table::contains(&store.subscriptions, subscription_id), 
            ERR_SUBSCRIPTION_NOT_FOUND);
        let sub = table::borrow(&store.subscriptions, subscription_id);
        sub.end_time
    }

    public fun subscription_exists(subscription_id: u64): bool acquires SubscriptionStore {
        let store = borrow_global<SubscriptionStore>(@subscription);
        table::contains(&store.subscriptions, subscription_id)
    }

    public fun creator_has_subscribers(creator: address): bool acquires SubscriptionStore {
        let store = borrow_global<SubscriptionStore>(@subscription);
        table::contains(&store.creator_subscribers, creator)
    }

    public fun get_creator_subscribers_count(creator: address): u64 acquires SubscriptionStore {
        let store = borrow_global<SubscriptionStore>(@subscription);
        if (table::contains(&store.creator_subscribers, creator)) {
            vector::length(table::borrow(&store.creator_subscribers, creator))
        } else {
            0
        }
    }

    // FIXED: Don't return references to global state
    public fun get_user_active_subscription_ids(user: address): vector<u64> acquires UserSubscriptionHistory {
        if (!exists<UserSubscriptionHistory>(user)) {
            return vector::empty<u64>()
        };
        
        let history = borrow_global<UserSubscriptionHistory>(user);
        *&history.active_subscriptions // Return a copy instead of a reference
    }

    // FIXED: Don't return references to global state
    public fun get_subscription_details_by_id(subscription_id: u64): (u64, address, u64, address, u64, u64, u8, u64) acquires SubscriptionStore {
        let store = borrow_global<SubscriptionStore>(@subscription);
        assert!(table::contains(&store.subscriptions, subscription_id), 
            ERR_SUBSCRIPTION_NOT_FOUND);
        
        let sub = table::borrow(&store.subscriptions, subscription_id);
        (
            sub.id,
            sub.subscriber,
            sub.plan_id,
            sub.creator,
            sub.start_time,
            sub.end_time,
            sub.status,
            sub.payment_amount
        )
    }

    // Check if a subscription is active without returning references
    public fun is_subscription_active(subscription_id: u64): bool acquires SubscriptionStore {
        let store = borrow_global<SubscriptionStore>(@subscription);
        if (table::contains(&store.subscriptions, subscription_id)) {
            let sub = table::borrow(&store.subscriptions, subscription_id);
            sub.status == STATUS_ACTIVE && !time::is_subscription_expired(sub.end_time)
        } else {
            false
        }
    }

    public fun get_user_subscription_ids(user: address): vector<u64> acquires UserSubscriptionHistory {
        let result = vector::empty<u64>();
        if (!exists<UserSubscriptionHistory>(user)) {
            return result
        };
        
        let history = borrow_global<UserSubscriptionHistory>(user);
        let active_subs = &history.active_subscriptions;
        let len = vector::length(active_subs);
        let i = 0;
        
        while (i < len) {
            let sub_id = *vector::borrow(active_subs, i);
            vector::push_back(&mut result, sub_id);
            i = i + 1;
        };
        
        result
    }

    friend subscription::view;
}