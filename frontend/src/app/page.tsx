import { redirect } from "next/navigation";

// Until auth is built, the app opens on the miner dashboard.
export default function Home() {
  redirect("/miner");
}
