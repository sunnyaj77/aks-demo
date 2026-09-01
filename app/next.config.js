/** @type {import('next').NextConfig} */
const nextConfig = {
  // Standalone output produces a minimal, self-contained server bundle
  // (node_modules trimmed to only what's needed) — this is what makes
  // the production Docker image small and fast to start on AKS.
  output: 'standalone',
  reactStrictMode: true,
};

module.exports = nextConfig;
