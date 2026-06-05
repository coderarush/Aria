import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Relative base so the built site works from any path (GitHub Pages subfolder included).
export default defineConfig({
  plugins: [react()],
  base: "./",
});
