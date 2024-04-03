// The 'pondo' program.
program pondo.aleo {
  const PRECISION: i128 = 1000i128;
  const PRECISION_UNSIGNED: u128 = 1000u128;
  const PORTION_1: u128 = 400u128;
  const PORTION_2: u128 = 250u128;
  const PORTION_3: u128 = 160u128;
  const PORTION_4: u128 = 110u128;
  const PORTION_5: u128 = 80u128;
  const MINIMUM_BOND_POOL: u64 = 125_000_000u64; // microcredits
  const PROFITABILITY_TIMEFRAME: u32 = 40_000u32; // 1 week of blocks

  const MINIMUM_BOOST: u64 = 5_000_000u64;

  const DELEGATOR_1: address = aleo1wjgkfxahkpk6u48eu084dwnyenlamuw6k2vvfzxds786pdzntu9s4r9ds4;
  const DELEGATOR_2: address = aleo16954qfpx6jrtm7u094tz2jqm986w520j6ewe6xeju6ptyer6k5ysyknyxc;
  const DELEGATOR_3: address = aleo1hhf39eql5d4gvfwyga0trnzrj0cssvlyzt24w9eaczppvya05u9q695djt;
  const DELEGATOR_4: address = aleo1zmpnd8p29h0296uxpnmn4qqu9hukr6p4glwk6cpwln8huvdn7q9sl4vr7k;
  const DELEGATOR_5: address = aleo1xwa8pc6v9zypyaeqe4v65v8kw7mmstq54vnjnc8lwn874nt455rsus6d8n;
  const CORE_PROTOCOL: address = aleo1v7zqs7fls3ryy8dvtl77ytszk4p9af9mxx2kclq529jd3et7hc8qqlhsq0;
  const ALE: address = aleo1zpy3xyaf40uqt6v42wm8f9kzp7rhzrjy34kv5yyx3va4r9hgcsxstggn0q;
  const AXEL: address = aleo1fwwj46afvuv7n940zjmkn0vjp3fz3n5vnmz7gqgafxmzuym0w5gqad7hxq;

  struct state {
    stake: u64,
    reward: u64,
    performance: u64,
    unbond_amount: u64,
    validator: address,
    ideal_portion: u128
  }

  mapping boost_pool: address => u64;

  mapping portion_delegator: u128 => address;
  mapping delegator_performance: address => u64;

  mapping delegator_state: address => state;

  // 0u8 -> total amount of publicly held aleo in the protocol
  // should increase with deposits and decrease with bonding those deposits
  // should increase with boosting and decrease with final rebonding in the rebalance
  // 1u8 -> total amount of aleo pending withdraw
  mapping core_protocol_balance: u8 => u64;

  // u8 -> the height at which the last rebalance completed
  // should be updated at the end of the rebalance
  // used to estimate rewards earned since rebalancing
  mapping last_rebalance_height: u8 => u32;

  /* protocol controls
  // 0u8 ->
  // 0u8: protocol functioning as normal
  // 1u8: upcoming protocol rebalance
  // 2u8: upcoming protocol rebalance unbonding
  // 3u8: upcoming protocol mint rewards and protocol fee
  // 4u8: upcoming protocol rebalance redistribution
  // 10u8: protocol withdraw unbonding in progress
  */
  mapping protocol_state: u8 => u8;


  mapping withdraw_pool: u32 => u64;
  const WITHDRAW_WAIT_MINIMUM: u32 = 15_000u32; // aproximately 2.5 days' of blocks
  const WITHDRAW_FEE: u128 = 30u128; // out of 1000, 3% fee



  transition deposit_private(
    private input_record: credits.aleo/credits,
    public credits_deposit: u64,
    public referrer: address,
    public ale_to_mint: u64
  ) -> credits.aleo/credits {
    // transfer aleo to pool
    let updated_record: credits.aleo/credits = credits.aleo/transfer_private_to_public(input_record, CORE_PROTOCOL, credits_deposit);
    ale.aleo/mint_private(ale_to_mint, self.caller);

    return (updated_record) then finalize(credits_deposit, ale_to_mint);
  }

  finalize deposit_private(
    public credits_deposit: u64,
    public expected_paleo_mint: u64
  ) {
    // TODO: get total aleo by checking each delegator's bonded balance
    let total_aleo: u64 = total_ale_pool + credits_deposit;
    let pool_balance: u64 = core_protocol_balance.get_or_use(0u8, 0u64);

    // TODO: get paleo pool from external mapping
    let paleo_pool: u64 = total_ale_minted - total_ale_burned;

    // Confirm ale mint amoount
    let aleo_pool: u128 = total_aleo as u128;
    let paleo_mint_amount: u64 = get_paleo_mint_amount(aleo_pool, credits_deposit as u128, paleo_pool as u128);
    assert(paleo_mint_amount >= 1u64);
    assert(paleo_mint_amount >= expected_paleo_mint);

    // Update deposit pool
    pool_balance += credits_deposit;
    core_protocol_balance.set(0u8, pool_balance);
  }

  // TODO: deposit_public ??

  inline get_paleo_mint_amount(total_aleo: u128, deposit: u128, paleo: u128) -> u64 {
    let new_total_paleo: u128 = (paleo * PRECISION_UNSIGNED) * (total_aleo + deposit) / (total_aleo * PRECISION_UNSIGNED);
    let diff: u128 = new_total_paleo - paleo;
    let paleo_to_mint: u64 = diff as u64;
    return paleo_to_mint;
  }

  transition bond_deposit_pool(
    validators: [address; 5],
    transfer_amounts: [u64; 5]
  ) {
    // Transfer to each validator
    credits.aleo/transfer_public(DELEGATOR_1, transfer_amounts[0u8]);
    delegator1.aleo/bond(validators[0u8], transfer_amounts[0u8]);

    credits.aleo/transfer_public(DELEGATOR_2, transfer_amounts[1u8]);
    delegator2.aleo/bond(validators[1u8], transfer_amounts[1u8]);

    credits.aleo/transfer_public(DELEGATOR_3, transfer_amounts[2u8]);
    delegator3.aleo/bond(validators[2u8], transfer_amounts[2u8]);

    credits.aleo/transfer_public(DELEGATOR_4, transfer_amounts[3u8]);
    delegator4.aleo/bond(validators[3u8], transfer_amounts[3u8]);

    credits.aleo/transfer_public(DELEGATOR_5, transfer_amounts[4u8]);
    delegator5.aleo/bond(validators[4u8], transfer_amounts[4u8]);

    return then finalize(validators, transfer_amounts);
  }

  finalize bond_deposit_pool(
    validators: [address; 5],
    transfer_amounts: [u64; 5]
  ) {
    // ********** ASSERT INPUTS AND STATE **********
    // Confirm bonding is allowed TODO: bonding should be allowed during withdrawals
    let curr_protocol_state: u8 = protocol_state.get(0u8);
    let bonding_allowed: bool = curr_protocol_state == 0u8 || curr_protocol_state == 3u8;
    assert(bonding_allowed);

    // Confirm we have the minimum amount
    let pool_balance: u64 = core_protocol_balance.get_or_use(0u8, 0u64);
    assert(pool_balance >= MINIMUM_BOND_POOL);

    // Confirm transfer amounts are correct, update balances
    let total_transfer: u64 = transfer_amounts[0u8] + transfer_amounts[1u8] + transfer_amounts[2u8] + transfer_amounts[3u8] + transfer_amounts[4u8];
    let d1_state: state = delegator_state.get(DELEGATOR_1);
    let d2_state: state = delegator_state.get(DELEGATOR_2);
    let d3_state: state = delegator_state.get(DELEGATOR_3);
    let d4_state: state = delegator_state.get(DELEGATOR_4);
    let d5_state: state = delegator_state.get(DELEGATOR_5);

    let d1_transfer: u128 = d1_state.ideal_portion * total_transfer as u128 / PRECISION_UNSIGNED;
    let d2_transfer: u128 = d2_state.ideal_portion * total_transfer as u128 / PRECISION_UNSIGNED;
    let d3_transfer: u128 = d3_state.ideal_portion * total_transfer as u128 / PRECISION_UNSIGNED;
    let d4_transfer: u128 = d4_state.ideal_portion * total_transfer as u128 / PRECISION_UNSIGNED;
    let d5_transfer: u128 = d5_state.ideal_portion * total_transfer as u128 / PRECISION_UNSIGNED;

    assert_eq(transfer_amounts[0u8], d1_transfer as u64);
    assert_eq(transfer_amounts[1u8], d2_transfer as u64);
    assert_eq(transfer_amounts[2u8], d3_transfer as u64);
    assert_eq(transfer_amounts[3u8], d4_transfer as u64);
    assert_eq(transfer_amounts[4u8], d5_transfer as u64);

    assert_eq(validators[0u8], d1_state.validator);
    assert_eq(validators[1u8], d2_state.validator);
    assert_eq(validators[2u8], d3_state.validator);
    assert_eq(validators[3u8], d4_state.validator);
    assert_eq(validators[4u8], d5_state.validator);

    // Set new delegator state
    let new_d1_state: state = state {
      stake: d1_state.stake + transfer_amounts[0u8],
      reward: d1_state.reward,
      performance: d1_state.performance,
      unbond_amount: d1_state.unbond_amount,
      validator: d1_state.validator,
      ideal_portion: d1_state.ideal_portion
    };
    let new_d2_state: state = state {
      stake: d2_state.stake + transfer_amounts[1u8],
      reward: d2_state.reward,
      performance: d2_state.performance,
      unbond_amount: d2_state.unbond_amount,
      validator: d2_state.validator,
      ideal_portion: d2_state.ideal_portion
    };
    let new_d3_state: state = state {
      stake: d3_state.stake + transfer_amounts[2u8],
      reward: d3_state.reward,
      performance: d3_state.performance,
      unbond_amount: d3_state.unbond_amount,
      validator: d3_state.validator,
      ideal_portion: d3_state.ideal_portion
    };
    let new_d4_state: state = state {
      stake: d4_state.stake + transfer_amounts[3u8],
      reward: d4_state.reward,
      performance: d4_state.performance,
      unbond_amount: d4_state.unbond_amount,
      validator: d4_state.validator,
      ideal_portion: d4_state.ideal_portion
    };
    let new_d5_state: state = state {
      stake: d5_state.stake + transfer_amounts[4u8],
      reward: d5_state.reward,
      performance: d5_state.performance,
      unbond_amount: d5_state.unbond_amount,
      validator: d5_state.validator,
      ideal_portion: d5_state.ideal_portion
    };

    delegator_state.set(DELEGATOR_1, new_d1_state);
    delegator_state.set(DELEGATOR_2, new_d2_state);
    delegator_state.set(DELEGATOR_3, new_d3_state);
    delegator_state.set(DELEGATOR_4, new_d4_state);
    delegator_state.set(DELEGATOR_5, new_d5_state);

    // Subtract transfer amounts from pool
    pool_balance -= total_transfer;
    core_protocol_balance.set(0u8, pool_balance);
  }

  inline get_batch_height(height: u32) -> u32 {
    let min_block_height: u32 = height + WITHDRAW_WAIT_MINIMUM;
    let min_block_rounded_down: u32 = min_block_height / 10_000u32 * 10_000u32;
    let min_block_round_up: u32 = min_block_rounded_down + 10_000u32;
    return min_block_round_up;
  }

  transition create_withdraw_claim(
    private ale_record: ale.aleo/token,
    public current_height: u32,
    // total amount of ale to burn, including fee
    public ale_burn_amount: u64,
    // amount of credits to claim, minus fee
    public credits_claim_amount: u64
  ) {
    let withdraw_block: u32 = get_batch_height(current_height);
    ale.aleo/burn_private(ale_record, ale_burn_amount, credits_claim_amount, withdraw_block);
    // Mint fee to protocol in paleo
    let fee_calc: u128 = ale_burn_amount as u128 * WITHDRAW_FEE / PRECISION_UNSIGNED;
    let fee: u64 = fee_calc as u64;
    ale.aleo/mint_public(fee, AXEL);

    // Withdraw paleo less fee
    let net_ale_burn_amount: u64 = ale_burn_amount - fee;
    return then finalize(current_height, net_ale_burn_amount, withdraw_block, credits_claim_amount);
  }

  finalize create_withdraw_claim(
    current_height: u32,
    net_ale_burn_amount: u64,
    withdraw_block: u32,
    credits_withdraw: u64
  ) {
    assert(block.height <= current_height);
    let total_withdraw_amount: u64 = withdraw_pool.get_or_use(withdraw_block, 0u64);
    total_withdraw_amount = total_withdraw_amount + credits_withdraw;
    withdraw_pool.set(withdraw_block, total_withdraw_amount);

    let protocol_pending_withdraw_balance: u64 = core_protocol_balance.get_or_use(1u8, 0u64);
    let new_protocol_pending_withdraw_balance: u64 = protocol_pending_withdraw_balance + credits_withdraw;
    core_protocol_balance.set(1u8, new_protocol_pending_withdraw_balance);

    let d1_state: state = delegator_state.get(DELEGATOR_1);
    let d2_state: state = delegator_state.get(DELEGATOR_2);
    let d3_state: state = delegator_state.get(DELEGATOR_3);
    let d4_state: state = delegator_state.get(DELEGATOR_4);
    let d5_state: state = delegator_state.get(DELEGATOR_5);

    // ********** CONFIRM RATIO OF ALEO AND ALE POOLS **********
    // TODO: get total aleo by checking each delegator's bonded balance
    let pool_balance: u64 = core_protocol_balance.get_or_use(0u8, 0u64);
    let total_aleo_before: u64 = pool_balance;
    let total_aleo_after: u64 = total_aleo_before - credits_withdraw;

    let total_ale_before: u64 = total_ale_pool;
    let total_ale_after: u64 = total_ale_before - net_ale_burn_amount;

    // aleo_before / aleo_after should equal ale_before / ale_after
    // aleo_before * ale_after = aleo_after * ale_before

    let product_1: u128 = total_aleo_before as u128 * total_ale_after as u128;
    let product_2: u128 = total_aleo_after as u128 * total_ale_before as u128;
    assert_eq(product_1, product_2);
  }

  transition withdraw_unbond(
    public unbond_amounts: [u64; 5],
    public total_amount: u64,
    public withdraw_block: u32
    ) {
    assert_eq(total_amount, unbond_amounts[0u8] + unbond_amounts[1u8] + unbond_amounts[2u8] + unbond_amounts[3u8] + unbond_amounts[4u8]);
    delegator1.aleo/unbond(unbond_amounts[0u8]);
    delegator2.aleo/unbond(unbond_amounts[1u8]);
    delegator3.aleo/unbond(unbond_amounts[2u8]);
    delegator4.aleo/unbond(unbond_amounts[3u8]);
    delegator5.aleo/unbond(unbond_amounts[4u8]);

    return then finalize(unbond_amounts, total_amount, withdraw_block);
  }

  finalize withdraw_unbond(
    public unbond_amounts: [u64; 5],
    public total_amount: u64,
    public withdraw_block: u32
    ) {
    let d1_state: state = delegator_state.get(DELEGATOR_1);
    let d2_state: state = delegator_state.get(DELEGATOR_2);
    let d3_state: state = delegator_state.get(DELEGATOR_3);
    let d4_state: state = delegator_state.get(DELEGATOR_4);
    let d5_state: state = delegator_state.get(DELEGATOR_5);
    let saved_withdraw_amount: u64 = withdraw_pool.get_or_use(withdraw_block, 0u64);

    // ********** ASSERT INPUTS AND STATE **********
    assert_eq(saved_withdraw_amount, total_amount);

    // ********** ASSERT THAT DELEGATOR PROPORTIONS DO NOT CHANGE **********
    let curr_total_stake: u64 = d1_state.stake + d2_state.stake + d3_state.stake + d4_state.stake + d5_state.stake;
    let curr_d1_ratio: i128 = d1_state.stake as i128 * PRECISION / curr_total_stake as i128;
    let curr_d2_ratio: i128 = d2_state.stake as i128 * PRECISION / curr_total_stake as i128;
    let curr_d3_ratio: i128 = d3_state.stake as i128 * PRECISION / curr_total_stake as i128;
    let curr_d4_ratio: i128 = d4_state.stake as i128 * PRECISION / curr_total_stake as i128;
    let curr_d5_ratio: i128 = d5_state.stake as i128 * PRECISION / curr_total_stake as i128;

    let new_total_stake: i128 = curr_total_stake as i128 - total_amount as i128;
    let new_d1_stake: u64 = d1_state.stake - unbond_amounts[0u8];
    let new_d2_stake: u64 = d2_state.stake - unbond_amounts[1u8];
    let new_d3_stake: u64 = d3_state.stake - unbond_amounts[2u8];
    let new_d4_stake: u64 = d4_state.stake - unbond_amounts[3u8];
    let new_d5_stake: u64 = d5_state.stake - unbond_amounts[4u8];

    let new_d1_ratio: i128 = new_d1_stake as i128  * PRECISION / new_total_stake;
    let new_d2_ratio: i128 = new_d2_stake as i128  * PRECISION / new_total_stake;
    let new_d3_ratio: i128 = new_d3_stake as i128  * PRECISION / new_total_stake;
    let new_d4_ratio: i128 = new_d4_stake as i128  * PRECISION / new_total_stake;
    let new_d5_ratio: i128 = new_d5_stake as i128  * PRECISION / new_total_stake;

    assert_eq(curr_d1_ratio, new_d1_ratio);
    assert_eq(curr_d2_ratio, new_d2_ratio);
    assert_eq(curr_d3_ratio, new_d3_ratio);
    assert_eq(curr_d4_ratio, new_d4_ratio);
    assert_eq(curr_d5_ratio, new_d5_ratio);

    // ********** UPDATE DELEGATOR STATES **********
    let new_d1_state: state = state {
      stake: new_d1_stake,
      reward: d1_state.reward,
      performance: d1_state.performance,
      unbond_amount: unbond_amounts[0u8],
      validator: d1_state.validator,
      ideal_portion: d1_state.ideal_portion
    };

    let new_d2_state: state = state {
      stake: new_d2_stake,
      reward: d2_state.reward,
      performance: d2_state.performance,
      unbond_amount: unbond_amounts[1u8],
      validator: d2_state.validator,
      ideal_portion: d2_state.ideal_portion
    };

    let new_d3_state: state = state {
      stake: new_d3_stake,
      reward: d3_state.reward,
      performance: d3_state.performance,
      unbond_amount: unbond_amounts[2u8],
      validator: d3_state.validator,
      ideal_portion: d3_state.ideal_portion
    };

    let new_d4_state: state = state {
      stake: new_d4_stake,
      reward: d4_state.reward,
      performance: d4_state.performance,
      unbond_amount: unbond_amounts[3u8],
      validator: d4_state.validator,
      ideal_portion: d4_state.ideal_portion
    };

    let new_d5_state: state = state {
      stake: new_d5_stake,
      reward: d5_state.reward,
      performance: d5_state.performance,
      unbond_amount: unbond_amounts[4u8],
      validator: d5_state.validator,
      ideal_portion: d5_state.ideal_portion
    };

    delegator_state.set(DELEGATOR_1, new_d1_state);
    delegator_state.set(DELEGATOR_2, new_d2_state);
    delegator_state.set(DELEGATOR_3, new_d3_state);
    delegator_state.set(DELEGATOR_4, new_d4_state);
    delegator_state.set(DELEGATOR_5, new_d5_state);

    // *********** UPDATE PROTOCOL STATE **********
    assert_eq(protocol_state.get(0u8), 0u8);
    protocol_state.set(0u8, 10u8);

    let withdraw_pool_total: u64 = core_protocol_balance.get_or_use(1u8, 0u64);
    let new_withdraw_pool_total: u64 = withdraw_pool_total - total_amount;
    core_protocol_balance.set(1u8, new_withdraw_pool_total);
  }

  transition withdraw_claim_unbond(
    public unbond_amounts: [u64; 5]
    ) {
    // ********** CLAIM UNBOND AND SEND TO ALEO POOL OWNED BY ALE **********
    // note -- in the case that a validator has forcibly unbonded a delegator,
    // the fix_orphaned_delegator transition must be called
    delegator1.aleo/claim_unbond();
    delegator1.aleo/transfer_to_ale(unbond_amounts[0u8]);

    delegator2.aleo/claim_unbond();
    delegator2.aleo/transfer_to_ale(unbond_amounts[1u8]);

    delegator3.aleo/claim_unbond();
    delegator3.aleo/transfer_to_ale(unbond_amounts[2u8]);

    delegator4.aleo/claim_unbond();
    delegator4.aleo/transfer_to_ale(unbond_amounts[3u8]);

    delegator5.aleo/claim_unbond();
    delegator5.aleo/transfer_to_ale(unbond_amounts[4u8]);

    return then finalize(unbond_amounts);
  }

  finalize withdraw_claim_unbond(
    public unbond_amounts: [u64; 5]
    ) {
    let d1_state: state = delegator_state.get(DELEGATOR_1);
    let d2_state: state = delegator_state.get(DELEGATOR_2);
    let d3_state: state = delegator_state.get(DELEGATOR_3);
    let d4_state: state = delegator_state.get(DELEGATOR_4);
    let d5_state: state = delegator_state.get(DELEGATOR_5);

    // ********** ASSERT INPUTS AND STATE **********
    assert_eq(unbond_amounts[0u8], d1_state.unbond_amount);
    assert_eq(unbond_amounts[1u8], d2_state.unbond_amount);
    assert_eq(unbond_amounts[2u8], d3_state.unbond_amount);
    assert_eq(unbond_amounts[3u8], d4_state.unbond_amount);
    assert_eq(unbond_amounts[4u8], d5_state.unbond_amount);

    // ********** UPDATE DELEGATOR STATES **********
    let new_d1_state: state = state {
      stake: d1_state.stake,
      reward: d1_state.reward,
      performance: d1_state.performance,
      unbond_amount: 0u64,
      validator: d1_state.validator,
      ideal_portion: d1_state.ideal_portion
    };

    let new_d2_state: state = state {
      stake: d2_state.stake,
      reward: d2_state.reward,
      performance: d2_state.performance,
      unbond_amount: 0u64,
      validator: d2_state.validator,
      ideal_portion: d2_state.ideal_portion
    };

    let new_d3_state: state = state {
      stake: d3_state.stake,
      reward: d3_state.reward,
      performance: d3_state.performance,
      unbond_amount: 0u64,
      validator: d3_state.validator,
      ideal_portion: d3_state.ideal_portion
    };

    let new_d4_state: state = state {
      stake: d4_state.stake,
      reward: d4_state.reward,
      performance: d4_state.performance,
      unbond_amount: 0u64,
      validator: d4_state.validator,
      ideal_portion: d4_state.ideal_portion
    };

    let new_d5_state: state = state {
      stake: d5_state.stake,
      reward: d5_state.reward,
      performance: d5_state.performance,
      unbond_amount: 0u64,
      validator: d5_state.validator,
      ideal_portion: d5_state.ideal_portion
    };

    delegator_state.set(DELEGATOR_1, new_d1_state);
    delegator_state.set(DELEGATOR_2, new_d2_state);
    delegator_state.set(DELEGATOR_3, new_d3_state);
    delegator_state.set(DELEGATOR_4, new_d4_state);
    delegator_state.set(DELEGATOR_5, new_d5_state);

    // *********** CHECK & UPDATE PROTOCOL STATE **********
    assert_eq(protocol_state.get(0u8), 10u8);
    // withdraw claim finished, set protocol back to normal
    protocol_state.set(0u8, 0u8);
  }
}
