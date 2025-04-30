// module subscription::plans {
//     use std::signer;
//     use std::vector;
//     use aptos_std::option::{Self, Option};
//     use std::string::String;
//     use aptos_framework::event;
//     use aptos_framework::timestamp;
//     use aptos_std::table::{Self, Table};

//     use subscription::registry;

//     const ERR_NOT_AUTHORIZED: u64 = 1;
//     const ERR_PLAN_NOT_FOUND: u64 = 2;
//     const ERR_INVALID_DURATION: u64 = 3;
//     const ERR_INVALID_PRICE: u64 = 4;
//     const ERR_PLAN_INACTIVE: u64 = 5;
//     const ERR_CREATOR_NOT_FOUND: u64 = 6;

//     struct SubscriptionPlan has key, store {
//         id: u64,
//         creator: address,
//         title: String,
//         description: String,
//         price: u64,
//         duration: u64,
//         active: bool,
//         created_at: u64,
//         updated_at: u64
//     }

//     struct CreatorPlan has key {
//         plans: Table<address, vector<u64>>
//     }

//     struct PlanRegistry has key {
//         plans: Table<u64, SubscriptionPlan>
//     }

//     struct PlanCreatedEvent has drop, store {
//         plan_id: u64,
//         creator: address,
//         title: String,
//         price: u64,
//         duration: u64
//     }

//     struct PlanUpdatedEvent has drop, store {
//         plan_id: u64,
//         title_updated: bool,
//         description_updated: bool,
//         price_updated: bool,
//         active_updated: bool,
//         timestamp: u64
//     }

//     public entry fun initialize_plan_registry(admin: &signer) {
//         assert!(signer::address_of(admin) == @subscription, ERR_NOT_AUTHORIZED);
//          move_to(admin, PlanRegistry { plans: table::new() });
//         move_to(admin, CreatorPlan { plans: table::new() });
//     }

//     public entry fun create_plan(
//         creator: &signer,
//         title: String,
//         description: String,
//         price: u64,
//         duration: u64,
//         active: bool,
//     ) acquires PlanRegistry, CreatorPlan {
//         let plan_registry = borrow_global_mut<PlanRegistry>(@subscription);
//         let creator_addr = signer::address_of(creator);
//         assert!(registry::verify_caller_is_creator(creator), ERR_NOT_AUTHORIZED);
//         assert!(duration >= registry::get_min_subscription_duration(), ERR_INVALID_DURATION);
//         assert!(price > 0, ERR_INVALID_PRICE);

//         let plan_id = registry::generate_plan_id();
//         let current_time = timestamp::now_seconds();

//         let new_plan = SubscriptionPlan {
//             id: plan_id,
//             creator: creator_addr,
//             title,
//             description,
//             price,
//             duration,
//             active,
//             created_at: current_time,
//             updated_at: current_time,
//         };

//         let plan_registry = borrow_global_mut<PlanRegistry>(@subscription);
//         table::add(&mut plan_registry.plans, plan_id, new_plan);

//         let creator_plans = borrow_global_mut<CreatorPlan>(@subscription);
//         if (!table::contains(&creator_plans.plans, creator_addr)) {
//             table::add(&mut creator_plans.plans, creator_addr, vector::empty<u64>());
//         };

//         let creator_plan_list = table::borrow_mut(&mut creator_plans.plans, creator_addr);
//         vector::push_back(creator_plan_list, plan_id);

//         event::emit(PlanCreatedEvent {
//             plan_id,
//             creator: creator_addr,
//             title,
//             price,
//             duration,
//         });
//     }

//     // public entry fun update_plan(
//     //     creator: &signer,
//     //     plan_id: u64,
//     //     title: Option<String>,
//     //     description: Option<String>,
//     //     price: Option<u64>,
//     //     active: Option<bool>,
//     // ) acquires PlanRegistry {
//     //     let creator_addr = signer::address_of(creator);
//     //     assert!(registry::verify_caller_is_creator(creator), ERR_NOT_AUTHORIZED);

//     //     let plan_registry = borrow_global_mut<PlanRegistry>(@subscription);
//     //     assert!(table::contains(&plan_registry.plans, plan_id), ERR_PLAN_NOT_FOUND);

//     //     let plan = table::borrow_mut(&mut plan_registry.plans, plan_id);
//     //     assert!(plan.creator == creator_addr, ERR_NOT_AUTHORIZED);

//     //     let new_title = option::none<String>();
//     //     let new_description = option::none<String>();
//     //     let new_price = option::none<u64>();
//     //     let new_active = option::none<bool>();

//     //     let title_mut = title;
//     //     if (option::is_some(&title_mut)) {
//     //         let title_val = option::extract(&mut title_mut);
//     //         plan.title = title_val;
//     //         new_title = option::some(title_val);
//     //     };

//     //     let description_mut = description;
//     //     if (option::is_some(&description_mut)) {
//     //         let desc_val = option::extract(&mut description_mut);
//     //         plan.description = desc_val;
//     //         new_description = option::some(desc_val);
//     //     };

//     //     let price_mut = price;
//     //     if (option::is_some(&price_mut)) {
//     //         let price_val = option::extract(&mut price_mut);
//     //         assert!(price_val > 0, ERR_INVALID_PRICE);
//     //         plan.price = price_val;
//     //         new_price = option::some(price_val);
//     //     };

//     //     let active_mut = active;
//     //     if (option::is_some(&active_mut)) {
//     //         let active_val = option::extract(&mut active_mut);
//     //         plan.active = active_val;
//     //         new_active = option::some(active_val);
//     //     };

//     //     plan.updated_at = timestamp::now_seconds();

//     //     event::emit(PlanUpdatedEvent {
//     //         plan_id,
//     //         title: new_title,
//     //         description: new_description,
//     //         price: new_price,
//     //         active: new_active,
//     //     });
//     // }

//     public entry fun update_plan(
//         creator: &signer,
//         plan_id: u64,
//         title: Option<String>,
//         description: Option<String>,
//         price: Option<u64>,
//         active: Option<bool>,
//     ) acquires PlanRegistry {
//         let creator_addr = signer::address_of(creator);
//         assert!(registry::verify_caller_is_creator(creator), ERR_NOT_AUTHORIZED);

//         let plan_registry = borrow_global_mut<PlanRegistry>(@subscription);
//         assert!(table::contains(&plan_registry.plans, plan_id), ERR_PLAN_NOT_FOUND);

//         let plan = table::borrow_mut(&mut plan_registry.plans, plan_id);
//         assert!(plan.creator == creator_addr, ERR_NOT_AUTHORIZED);

//         let title_updated = false;
//         let description_updated = false;
//         let price_updated = false;
//         let active_updated = false;

//         let title_mut = title;
//         if (option::is_some(&title_mut)) {
//             let title_val = option::extract(&mut title_mut);
//             plan.title = title_val;
//             title_updated = true;
//         };

//         let description_mut = description;
//         if (option::is_some(&description_mut)) {
//             let desc_val = option::extract(&mut description_mut);
//             plan.description = desc_val;
//             description_updated = true;
//         };

//         let price_mut = price;
//         if (option::is_some(&price_mut)) {
//             let price_val = option::extract(&mut price_mut);
//             assert!(price_val > 0, ERR_INVALID_PRICE);
//             plan.price = price_val;
//             price_updated = true;
//         };

//         let active_mut = active;
//         if (option::is_some(&active_mut)) {
//             let active_val = option::extract(&mut active_mut);
//             plan.active = active_val;
//             active_updated = true;
//         };

//         plan.updated_at = timestamp::now_seconds();

//         event::emit(PlanUpdatedEvent {
//             plan_id,
//             title_updated,
//             description_updated,
//             price_updated,
//             active_updated,
//             timestamp: timestamp::now_seconds()
//         });
//     }

//     public fun is_plan_active(plan_id: u64): bool acquires PlanRegistry {
//         let plan_registry = borrow_global<PlanRegistry>(@subscription);
//         if (!table::contains(&plan_registry.plans, plan_id)) {
//             return false
//         };
//         let plan = table::borrow(&plan_registry.plans, plan_id);
//         plan.active
//     }

//     public fun get_creator_plans(creator: address): &vector<u64> acquires CreatorPlan {
//         let creator_plan = borrow_global<CreatorPlan>(@subscription);
//         assert!(table::contains(&creator_plan.plans, creator), ERR_CREATOR_NOT_FOUND);
//         table::borrow(&creator_plan.plans, creator)
//     }


//     public fun get_plan(plan_id: u64): (address, String, u64, u64, bool) acquires PlanRegistry {
//         let plan_registry = borrow_global<PlanRegistry>(@subscription);
//         assert!(table::contains(&plan_registry.plans, plan_id), ERR_PLAN_NOT_FOUND);
//         let plan = table::borrow(&plan_registry.plans, plan_id);
//         (plan.creator, plan.title, plan.price, plan.duration, plan.active)
//     }

//     public fun assert_plan_subscribable(plan_id: u64) acquires PlanRegistry {
//         let plan_registry = borrow_global<PlanRegistry>(@subscription);
//         assert!(table::contains(&plan_registry.plans, plan_id), ERR_PLAN_NOT_FOUND);
//         let plan = table::borrow(&plan_registry.plans, plan_id);
//         assert!(plan.active, ERR_PLAN_INACTIVE);
//     }

//     public fun creator_has_plans(creator: address): bool acquires CreatorPlan {
//         let creator_plan = borrow_global<CreatorPlan>(@subscription);
//         table::contains(&creator_plan.plans, creator)
//     }

//     public fun get_creator_plan_struct(): &CreatorPlan acquires CreatorPlan {
//         borrow_global<CreatorPlan>(@subscription)
//     }

//     public fun get_plan_registry(): &PlanRegistry acquires PlanRegistry {
//         borrow_global<PlanRegistry>(@subscription)
//     }

//     friend subscription::subscriptions;
//     friend subscription::view;
// }

module subscription::plans {
    use std::signer;
    use std::vector;
    use aptos_std::option::{Self, Option};
    use std::string::String;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};

    use subscription::registry;

    const ERR_NOT_AUTHORIZED: u64 = 1;
    const ERR_PLAN_NOT_FOUND: u64 = 2;
    const ERR_INVALID_DURATION: u64 = 3;
    const ERR_INVALID_PRICE: u64 = 4;
    const ERR_PLAN_INACTIVE: u64 = 5;
    const ERR_CREATOR_NOT_FOUND: u64 = 6;

    struct SubscriptionPlan has key, store {
        id: u64,
        creator: address,
        title: String,
        description: String,
        price: u64,
        duration: u64,
        active: bool,
        created_at: u64,
        updated_at: u64,
        
    }

    struct CreatorPlan has key {
        plans: Table<address, vector<u64>>
    }

    struct PlanRegistry has key {
        plans: Table<u64, SubscriptionPlan>,
        plan_create_event:event::EventHandle<PlanCreatedEvent>,
        plan_update_event:event::EventHandle<PlanUpdatedEvent>
    }

    struct PlanCreatedEvent has drop, store {
        plan_id: u64,
        creator: address,
        title: String,
        price: u64,
        duration: u64
    }

    struct PlanUpdatedEvent has drop, store {
        plan_id: u64,
        title_updated: bool,
        description_updated: bool,
        price_updated: bool,
        active_updated: bool,
        timestamp: u64
    }

    public entry fun initialize_plan_registry(admin: &signer) {
        assert!(signer::address_of(admin) == @subscription, ERR_NOT_AUTHORIZED);
        move_to(admin, PlanRegistry { plans: table::new(),
        plan_create_event:account::new_event_handle<PlanCreatedEvent>(admin),
        plan_update_event:account::new_event_handle<PlanUpdatedEvent>(admin)
         });
        move_to(admin, CreatorPlan { plans: table::new() });
    }

    public entry fun create_plan(
        creator: &signer,
        title: String,
        description: String,
        price: u64,
        duration: u64,
        active: bool,
    ) acquires PlanRegistry, CreatorPlan {
        let plan_registry = borrow_global_mut<PlanRegistry>(@subscription);
        let creator_addr = signer::address_of(creator);
        assert!(registry::verify_caller_is_creator(creator), ERR_NOT_AUTHORIZED);
        assert!(duration >= registry::get_min_subscription_duration(), ERR_INVALID_DURATION);
        assert!(price > 0, ERR_INVALID_PRICE);

        let plan_id = registry::generate_plan_id();
        let current_time = timestamp::now_seconds();

        let new_plan = SubscriptionPlan {
            id: plan_id,
            creator: creator_addr,
            title,
            description,
            price,
            duration,
            active,
            created_at: current_time,
            updated_at: current_time,
        };

        table::add(&mut plan_registry.plans, plan_id, new_plan);

        let creator_plans = borrow_global_mut<CreatorPlan>(@subscription);
        if (!table::contains(&creator_plans.plans, creator_addr)) {
            table::add(&mut creator_plans.plans, creator_addr, vector::empty<u64>());
        };

        let creator_plan_list = table::borrow_mut(&mut creator_plans.plans, creator_addr);
        vector::push_back(creator_plan_list, plan_id);

        event::emit_event(&mut plan_registry.plan_create_event, PlanCreatedEvent {
            plan_id,
            creator: creator_addr,
            title,
            price,
            duration,
        });
    }

    public entry fun update_plan(
        creator: &signer,
        plan_id: u64,
        title: Option<String>,
        description: Option<String>,
        price: Option<u64>,
        active: Option<bool>,
    ) acquires PlanRegistry {
        let creator_addr = signer::address_of(creator);
        assert!(registry::verify_caller_is_creator(creator), ERR_NOT_AUTHORIZED);

        let plan_registry = borrow_global_mut<PlanRegistry>(@subscription);
        assert!(table::contains(&plan_registry.plans, plan_id), ERR_PLAN_NOT_FOUND);

        let plan = table::borrow_mut(&mut plan_registry.plans, plan_id);
        assert!(plan.creator == creator_addr, ERR_NOT_AUTHORIZED);

        let title_updated = false;
        let description_updated = false;
        let price_updated = false;
        let active_updated = false;

        let title_mut = title;
        if (option::is_some(&title_mut)) {
            let title_val = option::extract(&mut title_mut);
            plan.title = title_val;
            title_updated = true;
        };

        let description_mut = description;
        if (option::is_some(&description_mut)) {
            let desc_val = option::extract(&mut description_mut);
            plan.description = desc_val;
            description_updated = true;
        };

        let price_mut = price;
        if (option::is_some(&price_mut)) {
            let price_val = option::extract(&mut price_mut);
            assert!(price_val > 0, ERR_INVALID_PRICE);
            plan.price = price_val;
            price_updated = true;
        };

        let active_mut = active;
        if (option::is_some(&active_mut)) {
            let active_val = option::extract(&mut active_mut);
            plan.active = active_val;
            active_updated = true;
        };

        plan.updated_at = timestamp::now_seconds();

        event::emit_event(&mut plan_registry.plan_update_event,PlanUpdatedEvent {
            plan_id,
            title_updated,
            description_updated,
            price_updated,
            active_updated,
            timestamp: timestamp::now_seconds()
        });
    }

    public fun is_plan_active(plan_id: u64): bool acquires PlanRegistry {
        let plan_registry = borrow_global<PlanRegistry>(@subscription);
        if (!table::contains(&plan_registry.plans, plan_id)) {
            return false
        };
        let plan = table::borrow(&plan_registry.plans, plan_id);
        plan.active
    }

    // public fun get_creator_plans(creator: address): vector<u64> acquires CreatorPlan {
    //     let creator_plan = borrow_global<CreatorPlan>(@subscription);
    //     assert!(table::contains(&creator_plan.plans, creator), ERR_CREATOR_NOT_FOUND);
    //     let plans_ref = table::borrow(&creator_plan.plans, creator);
    //     let copied_ref = copy plans_ref;

    //     return copied_ref
    // }

    public fun get_creator_plans(creator: address): vector<u64> acquires CreatorPlan {
        let creator_plan = borrow_global<CreatorPlan>(@subscription);
        assert!(table::contains(&creator_plan.plans, creator), ERR_CREATOR_NOT_FOUND);
        let plans_ref = table::borrow(&creator_plan.plans, creator); // &vector<u64>

        // Clone the vector<u64>
        let copied = vector::empty<u64>();
        let len = vector::length(plans_ref);
        let i = 0;
        while (i < len) {
            let val = *vector::borrow(plans_ref, i);
            vector::push_back(&mut copied, val);
            i = i + 1;
        };
        copied
    }


    public fun get_plan(plan_id: u64): (address, String, u64, u64, bool) acquires PlanRegistry {
        let plan_registry = borrow_global<PlanRegistry>(@subscription);
        assert!(table::contains(&plan_registry.plans, plan_id), ERR_PLAN_NOT_FOUND);
        let plan = table::borrow(&plan_registry.plans, plan_id);
        (plan.creator, plan.title, plan.price, plan.duration, plan.active)
    }

    public fun assert_plan_subscribable(plan_id: u64) acquires PlanRegistry {
        let plan_registry = borrow_global<PlanRegistry>(@subscription);
        assert!(table::contains(&plan_registry.plans, plan_id), ERR_PLAN_NOT_FOUND);
        let plan = table::borrow(&plan_registry.plans, plan_id);
        assert!(plan.active, ERR_PLAN_INACTIVE);
    }

    public fun creator_has_plans(creator: address): bool acquires CreatorPlan {
        let creator_plan = borrow_global<CreatorPlan>(@subscription);
        table::contains(&creator_plan.plans, creator)
    }

    friend subscription::subscriptions;
    friend subscription::view;
}