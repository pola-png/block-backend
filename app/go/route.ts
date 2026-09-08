import { NextRequest, NextResponse } from "next/server";

export function GET(request: NextRequest) {
  const keyword =
    request.nextUrl.searchParams.get("q")?.trim() || "XapZap";

  const googleUrl = new URL("https://www.google.com/search");

  googleUrl.searchParams.set("q", keyword);

  return NextResponse.redirect(
    googleUrl.toString(),
    302
  );
}
