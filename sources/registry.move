module subscription::registry {
    use std::signer;
    use std::vector;
    use std::string::String;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::account;
    
    const ERR_NOT_AUTHORIZED: u64 = 1;
    const ERR_ALREADY_REGISTERED: u64 = 2;
    const ERR_CREATOR_NOT_FOUND: u64 = 3;
    const ERR_REGISTRY_ALREADY_EXISTS: u64 = 4;

    struct AdminCapability has key {
        admin_address: address 
    }

    struct CreatorCapability has key {
        creator_address: address
    }

    struct SubscriptionRegistry has key {
        platform_fee_percentage: u64,
        min_subscription_duration: u64,
        admin_address: address,
        next_plan_id: u64,
        next_subscription_id: u64,
        total_plans: u64,
        total_subscriptions: u64,
        active_subscriptions: u64,
        registry_initialized_event: event::EventHandle<RegistryInitializedEvent>,
        creator_registered_event: event::EventHandle<CreatorRegisteredEvent>,
        config_updated_event: event::EventHandle<ConfigUpdatedEvent>,
        creator_verification_event: event::EventHandle<CreatorVerificationEvent>
    }

    struct RegistryInitializedEvent has drop, store {
        admin: address,
        timestamp: u64
    }

    struct CreatorRegisteredEvent has drop, store {
        creator: address,
        timestamp: u64
    }

    struct ConfigUpdatedEvent has drop, store {
        fee_percentage: u64,
        min_duration: u64,
        timestamp: u64
    }

    struct CreatorVerificationEvent has drop, store {
        creator: address,
        is_verified: bool,
        timestamp: u64
    }

    public entry fun initialize(admin: &signer) acquires SubscriptionRegistry {
        let admin_addr = signer::address_of(admin);
        let registry = borrow_global_mut<SubscriptionRegistry>(@subscription);
        assert!(admin_addr == @subscription, ERR_NOT_AUTHORIZED);
        assert!(!exists<SubscriptionRegistry>(admin_addr), ERR_REGISTRY_ALREADY_EXISTS);

        move_to(admin, AdminCapability {
            admin_address: admin_addr
        });

        move_to(admin, SubscriptionRegistry {
            platform_fee_percentage: 250,
            min_subscription_duration: 86400,
            admin_address: admin_addr,
            next_plan_id: 0,
            next_subscription_id: 0,
            total_plans: 0,
            total_subscriptions: 0,
            active_subscriptions: 0,
            registry_initialized_event: account::new_event_handle<RegistryInitializedEvent>(admin),
            creator_registered_event: account::new_event_handle<CreatorRegisteredEvent>(admin),
            config_updated_event: account::new_event_handle<ConfigUpdatedEvent>(admin),
            creator_verification_event: account::new_event_handle<CreatorVerificationEvent>(admin)
        });

        event::emit_event(&mut registry.registry_initialized_event, RegistryInitializedEvent {
            admin: admin_addr,
            timestamp: timestamp::now_seconds(),
        });
    }

    public entry fun register_creator(creator : &signer) acquires SubscriptionRegistry {
        let creator_addr = signer::address_of(creator);
        let registry = borrow_global_mut<SubscriptionRegistry>(@subscription);
        assert!(!exists<CreatorCapability>(creator_addr), ERR_ALREADY_REGISTERED);

        move_to(creator, CreatorCapability {
            creator_address: creator_addr
        });

        event::emit_event(&mut registry.creator_registered_event, CreatorRegisteredEvent {
            creator: creator_addr,
            timestamp: timestamp::now_seconds()
        });
    }

    public entry fun update_global_config(
        admin: &signer,
        new_fee_percentage: u64,
        new_min_duration: u64
    ) acquires SubscriptionRegistry {
        assert!(signer::address_of(admin) == @subscription, ERR_NOT_AUTHORIZED); 

        let registry = borrow_global_mut<SubscriptionRegistry>(@subscription);
        registry.platform_fee_percentage = new_fee_percentage;
        registry.min_subscription_duration = new_min_duration;

        event::emit_event(&mut registry.config_updated_event, ConfigUpdatedEvent {
            fee_percentage: new_fee_percentage,
            min_duration: new_min_duration,
            timestamp: timestamp::now_seconds()
        });
    }

    public fun generate_plan_id(): u64 acquires SubscriptionRegistry {
        let registry = borrow_global_mut<SubscriptionRegistry>(@subscription);
        let plan_id = registry.next_plan_id;
        registry.next_plan_id = plan_id + 1;
        registry.total_plans = registry.total_plans + 1;
        plan_id
    }

    public fun generate_subscription_id(): u64 acquires SubscriptionRegistry {
        let registry = borrow_global_mut<SubscriptionRegistry>(@subscription);
        let subscription_id = registry.next_subscription_id;
        registry.next_subscription_id = subscription_id + 1;
        subscription_id
    }

    public fun decrease_active_subscriptions() acquires SubscriptionRegistry {
        let registry = borrow_global_mut<SubscriptionRegistry>(@subscription);
        if (registry.active_subscriptions > 0) {
            registry.active_subscriptions = registry.active_subscriptions - 1;
        };
    }

    public fun get_min_subscription_duration(): u64 acquires SubscriptionRegistry {
        borrow_global<SubscriptionRegistry>(@subscription).min_subscription_duration
    }

    public fun get_platform_fee_percentage(): u64 acquires SubscriptionRegistry {
        borrow_global<SubscriptionRegistry>(@subscription).platform_fee_percentage
    }

    public fun verify_admin(account: &signer): bool {
        exists<AdminCapability>(signer::address_of(account))
    }

    public fun verify_creator(account: address): bool {
        exists<CreatorCapability>(account)
    }

    public fun verify_caller_is_creator(account: &signer): bool {
        exists<CreatorCapability>(signer::address_of(account))
    }


}