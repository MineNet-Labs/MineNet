// Shown while a miner page loads.
export default function Loading() {
  return (
    <div className="space-y-5" aria-busy="true" aria-label="Loading">
      <div className="h-16 w-1/3 animate-pulse rounded-2xl bg-white" />
      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-4">
        {[0, 1, 2, 3].map((i) => <div key={i} className="h-28 animate-pulse rounded-[22px] bg-white" />)}
      </div>
      <div className="h-80 animate-pulse rounded-[22px] bg-white" />
    </div>
  );
}
