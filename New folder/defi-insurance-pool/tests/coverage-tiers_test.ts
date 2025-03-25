import { assertEquals } from "asserts";
import { Clarinet, Tx, Chain, Account } from "clarinet";
import { toHex } from "utils";

Clarinet.test({
  name: "Test adding a new coverage tier",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    let deployer = accounts.get("deployer")!;
    let tierName = "Basic Coverage";
    let tierAmount = 1000;

    // Add coverage tier
    let block = chain.mineBlock([
      Tx.contractCall("coverage-tiers", "add-tier", [toHex(tierName), tierAmount], deployer.address),
    ]);

    // Check if the tier was added successfully
    assertEquals(block.receipts[0].result, `ok`);
  },
});

Clarinet.test({
  name: "Test modifying an existing coverage tier",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    let deployer = accounts.get("deployer")!;
    let tierName = "Basic Coverage";
    let newTierAmount = 1500;

    // Modify coverage tier
    let block = chain.mineBlock([
      Tx.contractCall("coverage-tiers", "modify-tier", [toHex(tierName), newTierAmount], deployer.address),
    ]);

    // Check if the tier was modified successfully
    assertEquals(block.receipts[0].result, `ok`);
  },
});

Clarinet.test({
  name: "Test retrieving coverage tiers",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    let deployer = accounts.get("deployer")!;
    let tierName = "Basic Coverage";

    // Retrieve coverage tier
    let block = chain.mineBlock([
      Tx.contractCall("coverage-tiers", "get-tier", [toHex(tierName)], deployer.address),
    ]);

    // Check if the tier is returned correctly
    assertEquals(block.receipts[0].result, `ok`);
  },
});