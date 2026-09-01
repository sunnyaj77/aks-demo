// Used by the Kubernetes liveness AND readiness probes (see
// charts/nextjs-app/templates/deployment.yaml). Keep this fast and
// dependency-free — if it starts doing DB calls, a slow DB will make
// Kubernetes think healthy pods are broken and restart them.
export default function handler(req, res) {
  res.status(200).json({
    status: 'ok',
    pod: process.env.HOSTNAME || 'unknown',
    uptimeSeconds: Math.round(process.uptime()),
  });
}
