import { NextRequest, NextResponse } from 'next/server'
import {
  MONTHLY_PLAN_PRICE_USD,
  convertUsdToCurrency,
  detectCountryFromHeaders,
  fetchUsdRates,
  formatCurrency,
  resolveCheckoutCurrency,
} from '../../../../../lib/billing'

export async function GET(request: NextRequest) {
  try {
    const country = detectCountryFromHeaders(request.headers)
    const currencyData = resolveCheckoutCurrency(country)
    const rates = await fetchUsdRates()

    const basicAmount = convertUsdToCurrency(
      MONTHLY_PLAN_PRICE_USD.basic,
      currencyData.checkoutCurrency,
      rates
    )
    const businessAmount = convertUsdToCurrency(
      MONTHLY_PLAN_PRICE_USD.business,
      currencyData.checkoutCurrency,
      rates
    )

    return NextResponse.json({
      country: currencyData.country,
      currency: currencyData.checkoutCurrency,
      countryCurrency: currencyData.countryCurrency,
      usedFallbackCurrency: currencyData.usedFallbackCurrency,
      monthly: {
        basic: basicAmount,
        business: businessAmount,
      },
      formatted: {
        basic: formatCurrency(basicAmount, currencyData.checkoutCurrency),
        business: formatCurrency(businessAmount, currencyData.checkoutCurrency),
      },
      usdBase: MONTHLY_PLAN_PRICE_USD,
    })
  } catch (error: any) {
    return NextResponse.json(
      {
        error: error?.message || 'Failed to resolve pricing',
      },
      { status: 500 }
    )
  }
}

