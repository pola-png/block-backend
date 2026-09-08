export default function Loading() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-[rgb(var(--bg-primary))]">
      <div className="h-10 w-10 rounded-full border-2 border-[rgb(var(--accent-blue))] border-t-transparent animate-spin" />
    </div>
  )
}