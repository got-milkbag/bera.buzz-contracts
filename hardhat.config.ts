import "dotenv/config";

import {HardhatUserConfig} from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

require("dotenv").config();

const config: HardhatUserConfig = {
    solidity: {
        compilers: [
            {
                version: "0.8.19",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        ],
    },
    paths: {
        artifacts: "./artifacts",
    },
    networks: {
        hardhat: {
            // chainId: 31337,
            forking: {
                url: "https://berachain-bartio.g.alchemy.com/v2/vyOEZETX2qPyU9t1aYB5a7mwyTIqEpkQ",
                blockNumber: 4940400,
            },
        },
        berachainTestnet: {
            chainId: 80084,
            url: "https://bartio.rpc.berachain.com/",
            accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
        },
    },
};

export default config;
