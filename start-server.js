const { execSync } = require("child_process");
const net = require("net");

function isPortFree(port) {
  return new Promise((resolve) => {
    const server = net.createServer();
    server.once("error", () => resolve(false));
    server.once("listening", () => {
      server.close();
      resolve(true);
    });
    server.listen(port);
  });
}

async function findFreePort(start, end) {
  for (let port = start; port <= end; port++) {
    if (await isPortFree(port)) return port;
  }
  throw new Error(`No free port found between ${start} and ${end}`);
}

async function main() {
  const port = await findFreePort(3000, 3010);
  console.log(`Starting on port ${port}`);
  execSync(`npx next start -p ${port}`, { stdio: "inherit" });
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
