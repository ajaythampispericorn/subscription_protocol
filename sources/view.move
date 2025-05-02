module subscription::view {
    use std::string::String;
    use std::vector;
    use aptos_std::table;
    
    use subscription::plans;
    use subscription::subscriptions;
    use subscription::time;

    const STATUS_ACTIVE: u8 = 0;
    const STATUS_CANCELLED: u8 = 1;
    const STATUS_EXPIRED: u8 = 2;

    #[view]
    public fun get_plan_details(plan_id: u64): (address, String, u64, u64, bool) {
        plans::get_plan(plan_id)
    }

    #[view]
    public fun list_creator_plans(creator: address): vector<u64> {
        if (plans::creator_has_plans(creator)) {
            plans::get_creator_plans(creator)
        } else {
            vector::empty<u64>()
        }
    }

    #[view]
    public fun list_active_creator_plans(creator: address): vector<u64> {
        let result = vector::empty<u64>();
        let all_plans = plans::get_creator_plans(creator);
        let i = 0;
        let len = vector::length(&all_plans);
        
        while (i < len) {
            let plan_id = *vector::borrow(&all_plans, i);
            if (plans::is_plan_active(plan_id)) {
                vector::push_back(&mut result, plan_id);
            };
            i = i + 1;
        };
        result
    }

    #[view]
    public fun has_active_subscription(user: address, creator: address): bool {
        subscriptions::has_active_subscription(user, creator)
    }

    #[view]
    public fun get_subscription_details(subscription_id: u64): (address, u64, address, u64, u64, u8) {
        subscriptions::get_subscription(subscription_id)
    }

    #[view]
    public fun get_user_active_subscriptions(user: address): vector<u64> {
        let result = vector::empty<u64>();
        if (!subscriptions::user_has_history(user)) {
            return result
        };
        
        let subscription_ids = subscriptions::get_user_subscription_ids(user);
        
        let i = 0;
        let len = vector::length(&subscription_ids);

        while (i < len) {
            let sub_id = *vector::borrow(&subscription_ids, i);
            if (subscriptions::is_subscription_active(sub_id)) {
                vector::push_back(&mut result, sub_id);
            };
            i = i + 1;
        };

        result
    }

    #[view]
    public fun get_creator_subscriber_count(creator: address): u64 {
        subscriptions::get_creator_subscribers_count(creator)
    }
}