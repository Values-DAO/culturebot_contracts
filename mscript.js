const { StandardMerkleTree } = require("@openzeppelin/merkle-tree");
const fs = require("fs");
const { default: inquirer } = require("inquirer");

// Sample reward data - in production this would come from your data source
const rewards = [
    { address: "0x1234567890123456789012345678901234567890", index: 0, amount: "100000000000000000000" },
    { address: "0x2345678901234567890123456789012345678901", index: 1, amount: "200000000000000000000" },
    { address: "0x3456789012345678901234567890123456789012", index: 2, amount: "300000000000000000000" },
    { address: "0x4567890123456789012345678901234567890123", index: 3, amount: "400000000000000000000" }
];

// Format the values for the Merkle tree
const values = rewards.map(reward => [
    reward.address,
    reward.index.toString(),
    reward.amount
]);

// Create the Merkle tree
const tree = StandardMerkleTree.of(values, ["address", "uint256", "uint256"]);
const merkleRoot = tree.root;

// Generate claims mapping
const claims = {};
for (const [i, v] of tree.entries()) {
    const address = v[0];
    const proof = tree.getProof(i);

    claims[address] = {
        index: v[1],
        amount: v[2],
        proof: proof
    };
}

// Create the output object
const output = {
    merkleRoot: merkleRoot,
    claims: claims
};

// Save to JSON files
function saveToFile() {
    fs.writeFileSync(
        "merkle-tree-data.json",
        JSON.stringify(output, null, 2)
    );

    fs.writeFileSync(
        "merkle-tree-verification.json",
        JSON.stringify({
            root: merkleRoot,
            format: ["address", "uint256", "uint256"],
            values: values
        }, null, 2)
    );
}

// Verification helper function
function verifyAndGetProof(address) {
    const claim = claims[address];
    if (!claim) {
        return {
            success: false,
            message: "No claim found for this address",
            data: null
        };
    }

    const leaf = [address, claim.index.toString(), claim.amount];
    const isValid = tree.verify(claim.proof, leaf);

    return {
        success: isValid,
        message: isValid ? "Proof verified successfully" : "Proof verification failed",
        data: {
            address,
            index: claim.index,
            amount: claim.amount,
            proof: claim.proof,
            verified: isValid
        }
    };
}

// Function to display proof details
function displayProofDetails(proofResult) {
    if (!proofResult.success) {
        console.log("\n❌ Error:", proofResult.message);
        return;
    }

    const { data } = proofResult;
    console.log("\n✅ Proof Generated Successfully");
    console.log("\nClaim Details:");
    console.log("═══════════════");
    console.log(`Address: ${data.address}`);
    console.log(`Index:   ${data.index}`);
    console.log(`Amount:  ${data.amount} (in wei)`);
    console.log("\nProof Array:");
    console.log("════════════");
    console.log(data.proof);

    console.log("\nVerification Status:", data.verified ? "✅ Valid" : "❌ Invalid");

    // Save individual proof to file
    const proofFileName = `proof-${data.address.slice(0, 8)}.json`;
    fs.writeFileSync(
        proofFileName,
        JSON.stringify(data, null, 2)
    );
    console.log(`\nProof saved to ${proofFileName}`);
}

async function main() {
    try {
        // First prompt - ask if user wants to generate a proof
        const { generateProof } = await inquirer.prompt([
            {
                type: 'confirm',
                name: 'generateProof',
                message: 'Do you want to generate a proof for a specific address?',
                default: false
            }
        ]);

        // Generate and save the merkle tree data
        saveToFile();
        console.log("\n📦 Merkle tree data generated and saved");
        console.log(`🌳 Merkle Root: ${merkleRoot}`);

        if (generateProof) {
            // If yes, prompt for address
            const { address } = await inquirer.prompt([
                {
                    type: 'input',
                    name: 'address',
                    message: 'Enter the address to generate proof for:',
                    validate: function (input) {
                        if (/^0x[a-fA-F0-9]{40}$/.test(input)) {
                            return true;
                        }
                        return 'Please enter a valid Ethereum address';
                    }
                }
            ]);

            // Generate and display proof
            const proofResult = verifyAndGetProof(address);
            displayProofDetails(proofResult);
        }

    } catch (error) {
        console.error("An error occurred:", error);
    }
}
// Run the script
main();