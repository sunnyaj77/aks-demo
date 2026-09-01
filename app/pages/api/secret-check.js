import fs from 'fs';

// Demonstrates reading a secret that the Key Vault CSI driver mounted
// as a file into the pod (see secretproviderclass.yaml + the volumeMount
// in deployment.yaml). We only report presence/length, never the value —
// don't build an endpoint that echoes secret contents, even in a demo.
const SECRET_PATH = '/mnt/secrets-store/demo-api-key';

export default function handler(req, res) {
  try {
    const value = fs.readFileSync(SECRET_PATH, 'utf8');
    res.status(200).json({
      mounted: true,
      path: SECRET_PATH,
      length: value.length,
    });
  } catch (err) {
    res.status(200).json({
      mounted: false,
      path: SECRET_PATH,
      reason: err.code || String(err),
    });
  }
}
