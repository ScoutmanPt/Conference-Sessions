param([string]$currency="EUR")
function ListExchangeRates { param([string]$currency)
    [xml]$ExchangeRates = (invoke-webRequest -uri "http://www.floatrates.com/daily/$($currency).xml" -userAgent "curl" -useBasicParsing).Content 
    foreach($Row in $ExchangeRates.channel.item) {
        new-object PSObject -property @{ 'BaseName'="$($Row.baseName)";'Rate' = "$($Row.exchangeRate)"; 'Currency' = "$($Row.targetCurrency) - $($Row.targetName)"; 'Inverse' = "$($Row.inverseRate)"; 'Date' = "$($Row.pubDate)" }
    }
}

ListExchangeRates $currency | format-table -property BaseName,Rate,Currency,Inverse,Date