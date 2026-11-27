import Link from "next/link";

export default function MinerNotFound() {
  return (
    <div className="rounded-[22px] bg-white p-10 text-center">
      <h2>Page not found</h2>
      <p className="mt-2 text-ink/70">This page doesn&apos;t exist in the miner portal.</p>
      <Link href="/miner" className="mt-5 inline-block rounded-full bg-[#1F5B3A] px-6 py-3 font-medium text-white hover:bg-primary">Back to Overview</Link>
    </div>
  );
}
