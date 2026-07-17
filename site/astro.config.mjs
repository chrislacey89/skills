// @ts-check
import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";

// Project pages live at https://chrislacey89.github.io/skills/
export default defineConfig({
	site: "https://chrislacey89.github.io",
	base: "/skills",
	vite: {
		plugins: [tailwindcss()],
	},
});
