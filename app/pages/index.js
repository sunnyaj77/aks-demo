export default function Home({ podName, imageTag, region }) {
  return (
    <main style={{ fontFamily: 'sans-serif', padding: '3rem', maxWidth: 720 }}>
      <h1>🚀 AKS + FluxCD + GitHub Actions demo - v1</h1>
      <p>This Next.js app is running inside a pod on Azure Kubernetes Service.</p>
      <ul>
        <li><strong>Pod name:</strong> {podName}</li>
        <li><strong>Image tag:</strong> {imageTag}</li>
        <li><strong>Region (env):</strong> {region}</li>
      </ul>
      <p>
        Health check: <code>/api/health</code>
      </p>
    </main>
  );
}

// Server-side render so pod identity is read fresh on every request —
// useful for proving a rolling update actually reached this pod.
export async function getServerSideProps() {
  return {
    props: {
      podName: process.env.HOSTNAME || 'unknown',
      imageTag: process.env.IMAGE_TAG || 'not-set',
      region: process.env.AZURE_REGION || 'not-set',
    },
  };
}
