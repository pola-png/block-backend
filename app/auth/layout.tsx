import { RouteGuard } from '../../AuthWrapper'

export default function AuthLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <RouteGuard requireAuth={false}>
      {children}
    </RouteGuard>
  )
}