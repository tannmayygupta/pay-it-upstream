import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// base './' so the built app also works from a sub-path or an IPFS/Swarm gateway.
export default defineConfig({ base: "./", plugins: [react()] });
