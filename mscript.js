const { StandardMerkleTree } = require("@openzeppelin/merkle-tree");
const fs = require("fs");
const inquirer = require("inquirer");

// Sample reward data - in production this would come from your data source
const rewards = [
    { address: "0x1234567890123456789012345678901234567890", index: 0, amount: 100 },
    { address: "0x2345678901234567890123456789012345678901", index: 1, amount: 200 },
    { address: "0x3456789012345678901234567890123456789012", index: 2, amount: 300 },
    { address: "0x4567890123456789012345678901234567890123", index: 3, amount: 400 }
];

// Format the values for the Merkle tree
const values = rewards.map(reward => [
    reward.address,
    reward.index,
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

function getProof(address) {
    const claim = claims[address];
    if (!claim) {
        return {
            success: false,
            message: "No claim found for this address",
            data: null
        };
    }

    return {
        success: true,
        message: "Proof generated successfully",
        data: {
            address,
            index: claim.index,
            amount: claim.amount,
            proof: claim.proof
        }
    };
}

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

    const proofFileName = `proof-${data.address.slice(0, 8)}.json`;
    fs.writeFileSync(
        proofFileName,
        JSON.stringify(data, null, 2)
    );
    console.log(`\nProof saved to ${proofFileName}`);
}

async function main() {
    try {
        const { generateProof } = await inquirer.prompt([
            {
                type: 'confirm',
                name: 'generateProof',
                message: 'Do you want to generate a proof for a specific address?',
                default: false
            }
        ]);

        saveToFile();
        console.log("\n📦 Merkle tree data generated and saved");
        console.log(`🌳 Merkle Root: ${merkleRoot}`);

        if (generateProof) {
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

            const proofResult = getProof(address);
            displayProofDetails(proofResult);
        }

    } catch (error) {
        console.error("An error occurred:", error);
    }
}

main();