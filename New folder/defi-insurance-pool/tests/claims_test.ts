import { assertEquals } from "asserts";
import { Tx, Chain, Account } from "clarinet";
import { getAccount } from "./utils";

const account = getAccount("wallet_1");

describe("Claims Contract", () => {
    it("should allow a user to submit a claim", () => {
        const tx = new Tx(account.address, "submit-claim", {
            claimId: "claim_1",
            user: account.address,
            details: "Claim details here",
        });
        const result = Chain.processTx(tx);
        assertEquals(result.success, true);
    });

    it("should verify a submitted claim", () => {
        const tx = new Tx(account.address, "verify-claim", {
            claimId: "claim_1",
            verified: true,
        });
        const result = Chain.processTx(tx);
        assertEquals(result.success, true);
    });

    it("should process payout for a verified claim", () => {
        const tx = new Tx(account.address, "process-payout", {
            claimId: "claim_1",
            amount: 100,
        });
        const result = Chain.processTx(tx);
        assertEquals(result.success, true);
    });

    it("should not allow payout for an unverified claim", () => {
        const tx = new Tx(account.address, "process-payout", {
            claimId: "claim_2",
            amount: 50,
        });
        const result = Chain.processTx(tx);
        assertEquals(result.success, false);
    });
});