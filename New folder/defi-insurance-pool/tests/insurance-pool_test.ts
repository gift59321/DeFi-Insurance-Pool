import { assertEquals } from "asserts";
import { Clarinet, Tx, Chain, Account } from "clarinet";
import { toHex } from "utils";

Clarinet.test({
  name: "Test locking tokens in the insurance pool",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const user = accounts.get("wallet_1")!;
    const pool = accounts.get("wallet_2")!;

    // User locks tokens in the insurance pool
    let block = chain.mineBlock([
      Tx.contractCall("insurance-pool", "lock-tokens", [toHex("1000")], user.address),
    ]);
    block.receipts[0].result.expectOk().expectBool(true);

    // Check the balance in the pool
    const balance = chain.callReadOnlyFn("insurance-pool", "get-pool-balance", [], pool.address);
    balance.expectUint(1000);
  },
});

Clarinet.test({
  name: "Test processing payouts for verified claims",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const user = accounts.get("wallet_1")!;
    const pool = accounts.get("wallet_2")!;

    // Simulate a verified claim
    let block = chain.mineBlock([
      Tx.contractCall("insurance-pool", "process-payout", [toHex("500")], pool.address),
    ]);
    block.receipts[0].result.expectOk().expectBool(true);

    // Check the balance after payout
    const balance = chain.callReadOnlyFn("insurance-pool", "get-pool-balance", [], pool.address);
    balance.expectUint(500);
  },
});