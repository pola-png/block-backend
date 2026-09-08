export default function UploadLoading() {
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 p-4 backdrop-blur-sm">
      <div className="w-full max-w-sm rounded-2xl border border-[rgb(var(--border-color))] bg-[rgb(var(--bg-primary))] p-5 shadow-2xl">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-base font-semibold text-[rgb(var(--text-primary))]">Create Post</p>
            <p className="mt-1 text-sm text-[rgb(var(--text-secondary))]">Loading…</p>
          </div>
          <div className="h-8 w-8 animate-spin rounded-full border-2 border-[rgb(var(--border-color))] border-t-[rgb(var(--accent-blue))]" aria-label="Loading" />
        </div>
      </div>
    </div>
  )
}
