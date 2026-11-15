import { docsConfig } from "@timmo001/docs-kit/blume";
import { defineConfig } from "blume";

export default defineConfig(
  docsConfig({
    title: "Momentum",
    description:
      "A CLI and Omarchy panel for Sennheiser Momentum 4 headphones.",
    site: "momentumctl.timmo.dev",
    github: { owner: "timmo001", repo: "omarchy-momentumctl" },
    navigation: {
      sidebar: ["/", "/install", "/cli", "/panel", "/agents"],
    },
  }),
);
