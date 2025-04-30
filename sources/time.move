module subscription::time {
    use aptos_framework::timestamp;

    public fun calculate_end_time(start_time: u64, duration: u64): u64 {
        start_time + duration
    }

    public fun is_subscription_expired(end_time: u64): bool {
        timestamp::now_seconds() > end_time
    }

    public fun is_timestamp_past(check_time: u64): bool {
        timestamp::now_seconds() > check_time
    }

    public fun is_timestamp_future(check_time: u64): bool {
        timestamp::now_seconds() < check_time
    }

    public fun time_remaining(end_time: u64): u64 {
        let now = timestamp::now_seconds();

        if(now >= end_time) {
            0
        } else {
            end_time - now
        }
    }

    public fun percentage_elapsed(start_time: u64, end_time: u64): u64 {
        let total_duration = end_time - start_time;
        let now = timestamp::now_seconds();
        
        if (now <= start_time) {
            0
        } else if (now >= end_time) {
            100
        } else {
            ((now - start_time) * 100) / total_duration
        }
    }

    public fun calculate_remaining_value(payment_amount: u64, total_duration: u64, remaining_time: u64): u64 {
        if (total_duration == 0) {
            0
        } else {
            (payment_amount * remaining_time) / total_duration
        }
    }

    public fun calculate_prorated_duration(remaining_value: u64, new_plan_price: u64, new_plan_duration: u64): u64 {
        if (new_plan_price == 0) {
            0
        } else {
            (remaining_value * new_plan_duration) / new_plan_price
        }
    }

    public fun is_in_grace_period(end_time: u64, grace_period: u64): bool {
        let now = timestamp::now_seconds();
        now > end_time && now <= (end_time + grace_period)
    }
}
