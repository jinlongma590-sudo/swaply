// gen-apple-secret.mjs
// 用 Apple 的 .p8 私钥生成 client_secret (JWT)
// 运行示例：
// node gen-apple-secret.mjs --team KKMFJVK8MV --client cc.swaply.signin --keyid KDA77L7GJ5 --p8 ./AuthKey_KDA77L7GJ5.p8 --days 179

import fs from "fs";
import { SignJWT, importPKCS8 } from "jose";

function arg(flag, def = undefined) {
  const i = process.argv.indexOf(flag);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : def;
}

const TEAM_ID   = arg("--team");      // 你的 Team ID: KKMFJVK8MV
const CLIENT_ID = arg("--client");    // Service ID: cc.swaply.signin
const KEY_ID    = arg("--keyid");     // Key ID: KDA77L7GJ5
const P8_PATH   = arg("--p8");        // .p8 文件路径

const DAYS = parseInt(arg("--days", "179"), 10); // <= 180 天
const ALG  = "ES256";

if (!TEAM_ID || !CLIENT_ID || !KEY_ID || !P8_PATH) {
  console.error("\n缺少参数。示例：node gen-apple-secret.mjs --team KKMFJVK8MV --client cc.swaply.signin --keyid KDA77L7GJ5 --p8 ./AuthKey_KDA77L7GJ5.p8 --days 179\n");
  process.exit(1);
}

(async () => {
  const pem = fs.readFileSync(P8_PATH, "utf8");
  const key = await importPKCS8(pem, ALG);

  const now = Math.floor(Date.now() / 1000);
  const exp = now + Math.min(DAYS, 180) * 24 * 60 * 60;

  const jwt = await new SignJWT({})
    .setProtectedHeader({ alg: ALG, kid: KEY_ID })
    .setIssuer(TEAM_ID)                        // iss
    .setAudience("https://appleid.apple.com") // aud
    .setSubject(CLIENT_ID)                     // sub
    .setIssuedAt(now)
    .setExpirationTime(exp)
    .sign(key);

  console.log(jwt);
  fs.writeFileSync("apple_client_secret.jwt", jwt);
  console.error("\n已生成：apple_client_secret.jwt\n");
})();
