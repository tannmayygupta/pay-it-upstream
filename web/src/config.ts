import { createConfig, http } from "wagmi";
import { injected } from "wagmi/connectors";
import { foundry, sepolia } from "wagmi/chains";
import { isAddress } from "viem";

const env = import.meta.env;

export const chain = env.VITE_CHAIN === "anvil" ? foundry : sepolia;

const raw = (env.VITE_SPLITTER_ADDRESS as string | undefined) ?? "";
export const splitterAddress = (isAddress(raw) ? raw : undefined) as `0x${string}` | undefined;

const rpc = (env.VITE_RPC_URL as string | undefined) || undefined;

/** No backend: the page talks straight to an Ethereum RPC and to the user's wallet. */
export const wagmiConfig = createConfig({
  chains: [chain],
  connectors: [injected()],
  transports: { [chain.id]: http(rpc) } as Record<number, ReturnType<typeof http>>,
});

export const explorer = chain.id === sepolia.id ? "https://sepolia.etherscan.io" : undefined;
