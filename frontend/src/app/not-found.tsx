import Link from "next/link";

export default function NotFound() {
  return (
    <main className="grid min-h-screen place-items-center bg-page p-6">
      <div className="max-w-md rounded-[22px] bg-white p-10 text-center shadow-[0_4px_24px_rgba(17,24,39,0.06)]">
        <p className="font-brand text-[28px] font-bold"><span className="text-[#05581A]">Mine</span><span className="text-[#F57C00]">Net</span></p>
        <h1 className="mt-6 text-[32px]">Page not found</h1>
        <p className="mt-2 text-ink/70">This page doesn&apos;t exist or has moved.</p>
        <Link href="/miner" className="mt-6 inline-block rounded-full bg-[#1F5B3A] px-6 py-3 font-medium text-white hover:bg-primary">Go to dashboard</Link>
      </div>
    </main>
  );
}
