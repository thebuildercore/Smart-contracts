require("dotenv").config();
const { execSync, execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

async function compile() {
  // Check for publisher address
  const addr = process.env.VITE_MODULE_PUBLISHER_ACCOUNT_ADDRESS;
  if (!addr) {
    throw new Error(
      "VITE_MODULE_PUBLISHER_ACCOUNT_ADDRESS variable is not set. Add it to .env (e.g., VITE_MODULE_PUBLISHER_ACCOUNT_ADDRESS=0xYourAddress).",
    );
  }

  // If GLOBE_BUSINESS and GLOBE_CORE need different addresses, uncomment and set VITE_GLOBE_CORE_ADDRESS in .env
  // const coreAddr = process.env.VITE_GLOBE_CORE_ADDRESS || addr;
  // if (!coreAddr) {
  //   throw new Error("VITE_GLOBE_CORE_ADDRESS not set for GLOBE_CORE module.");
  // }

  // Prefer local aptos.exe for Windows compatibility
  const aptosPath = path.resolve(__dirname, "..", "..", "..", "aptos.exe");
  const useLocalAptos = fs.existsSync(aptosPath);

  try {
    const args = [
      "move",
      "compile",
      "--package-dir",
      "contract",
      "--named-addresses",
      `GLOBE_BUSINESS=${addr},GLOBE_CORE=${addr}`, // Map both to the same address
      // If using different addresses: `GLOBE_BUSINESS=${addr},GLOBE_CORE=${coreAddr}`,
    ];

    if (useLocalAptos) {
      console.log("Running:", aptosPath, args.slice(0, -1).join(" "), "...");
      execFileSync(aptosPath, args, { stdio: "inherit" });
    } else {
      console.log("Running via npx aptos move compile (fallback)");
      execFileSync("npx", ["aptos", ...args.slice(1)], { stdio: "inherit", shell: true });
    }

    console.log("✅ Compilation successful for GlobePayXCore.move and GlobePayXBusiness.move!");
  } catch (e) {
    console.error("❌ Compile failed:", e.message);
    console.error("Check: Move.toml, .env vars, contract/sources/GlobePayXBusiness.move, contract/sources/GlobePayXCore.move, and Aptos CLI version.");
    throw e;
  }
}

compile().catch(console.error);
