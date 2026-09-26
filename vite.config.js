import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "path";
import { createHash } from "crypto";
import { readFileSync, readdirSync } from "fs";

// Builds /sw.js from src/pwa/sw.template.js with the list of files to precache
// and a version that changes whenever the build output changes.
function serviceWorker() {
  return {
    name: "mimi-service-worker",
    apply: "build",
    generateBundle(_, bundle) {
      const built = Object.keys(bundle).filter((f) => /\.(js|css|woff2?|png|svg)$/.test(f)).map((f) => `/${f}`);
      const icons = readdirSync(path.resolve(__dirname, "public/icons")).map((f) => `/icons/${f}`);
      const brand = readdirSync(path.resolve(__dirname, "public/brand")).map((f) => `/brand/${f}`);
      const precache = ["/", "/index.html", "/manifest.json", ...icons, ...brand, ...built];
      const version = createHash("sha1").update(precache.join("|")).digest("hex").slice(0, 12);
      const source = readFileSync(path.resolve(__dirname, "src/pwa/sw.template.js"), "utf8")
        .replace("__VERSION__", version)
        .replace("__PRECACHE__", JSON.stringify(precache));
      this.emitFile({ type: "asset", fileName: "sw.js", source });
    },
  };
}

export default defineConfig({
  plugins: [react(), serviceWorker()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  server: {
    port: 3000,
  },
  build: {
    rollupOptions: {
      output: {
        // Keep big vendors in their own long-cached chunks.
        manualChunks: {
          firebase: ["firebase/app", "firebase/auth", "firebase/firestore", "firebase/storage"],
          react: ["react", "react-dom", "react-router-dom"],
          motion: ["framer-motion"],
        },
      },
    },
  },
});
