# MT5 Indicator Code Review: 10X_2_0_Indicator_Enhanced.mq5

## Summary

Review of the 10X 2.0 Enhanced Indicator for MetaTrader 5. The indicator detects bullish/bearish price action signals using lookback comparisons, candle structure analysis, multi-timeframe EMA trend filtering, ATR volatility filtering, and time-of-day filtering. Signals are scored 0-100 and displayed with entry zone visualization.

12 issues identified: 1 high severity, 3 medium, 2 low-medium, 5 low, 1 very low.

---

## Issues

### 1. Signal counter accumulation bug (HIGH)

**Location:** Lines 260-270, 337, 369

When `prev_calculated > 0` (every subsequent tick), the loop recalculates `limit = rates_total - prev_calculated + 1` bars. `CheckSignal` unconditionally increments `totalSignals`, `filteredSignals`, `validBuySignals`, and `validSellSignals`. Since the counters are only reset when `prev_calculated == 0`, every tick that recalculates recent bars re-counts signals on those bars, causing the stats panel numbers to inflate continuously.

**Impact:** Statistics panel shows incorrect (ever-growing) signal counts. Pass rate and signal totals become meaningless over time.

**Fix:** Either track which bars have already been counted, or recalculate counters from the buffer contents on each pass instead of incrementing globals.

---

### 2. Filter label objects never cleaned up (MEDIUM)

**Location:** Lines 265-266, 483

On full recalculation, objects with prefix `"zone_"` and `"lbl_"` are deleted, but objects with prefix `"flt_"` (created by `CreateFilterLabel`) are not.

**Impact:** Filter reason labels accumulate across recalculations and are only cleaned up on `OnDeinit`.

**Fix:** Add `ObjectsDeleteAll(0, objPrefix + "flt_");` alongside the existing cleanup calls.

---

### 3. Pip value wrong for 4-digit symbols (MEDIUM)

**Location:** Lines 872-875

```mql5
pipValue = (digits == 5) ? 0.0001 : 0.001;
```

For 4-digit non-JPY forex pairs (e.g., EURUSD on a 4-digit broker), pipValue should be `0.0001`, not `0.001`. The current code makes the SL buffer 10x too large and draws entry zones at incorrect levels.

**Fix:** Change to `pipValue = (digits == 5) ? 0.0001 : 0.0001;` or simply `pipValue = 0.0001;` for both cases. Alternatively, use `pipValue = MathPow(10, -(digits - 1));` for a more general approach.

---

### 4. BuyZoneColor / SellZoneColor inputs are unused (LOW)

**Location:** Lines 90-91, 425, 432-433

The variable `zoneColor` is computed on line 425 but never referenced. Zone rectangles use hardcoded colors instead of the user-configurable inputs.

**Impact:** Users can change these color inputs but see no effect.

**Fix:** Replace hardcoded colors in `DrawEntryZone` with `BuyZoneColor`/`SellZoneColor`.

---

### 5. SignalExpiryBars does not actually expire signals (MEDIUM)

**Location:** Lines 47, 423

The input says "Signal expires after X bars (0=no expiry)" but no logic suppresses signals after X bars. The value only controls the visual width of entry zone rectangles.

**Impact:** Misleading parameter name and description. Users expect signal expiry behavior.

**Fix:** Either implement actual signal expiry logic or rename the parameter to reflect its actual purpose (e.g., "Zone Display Width (bars)").

---

### 6. MinCandleBodyRatio not enforced as a filter (LOW-MEDIUM)

**Location:** Lines 46, 505-507

Named "Min body/range ratio" but only used for scoring (-15 penalty). Signals with tiny bodies (dojis) can still pass if MTF alignment boosts the score.

**Impact:** Parameter name implies a hard filter but acts as a soft scoring factor.

**Fix:** Either add a hard filter (`if(bodyRatio < MinCandleBodyRatio) return;` in `CheckSignal`) or rename to clarify it's a scoring weight.

---

### 7. ATR average includes the current bar (LOW)

**Location:** Lines 558-562

The average ATR loop starts at `j = 0`, including `atrValues[0]` (the value being compared) in its own average. This biases the ratio toward 1.0.

**Fix:** Start the averaging loop at `j = 1` and adjust the divisor, or copy one additional value and offset.

---

### 8. No MTF timeframe validation (LOW-MEDIUM)

**Location:** Lines 64-66, OnInit

No check that MTF timeframes are higher than the current chart timeframe. Applying to a D1 chart with default H4/H8/H12 MTF settings queries lower timeframes, producing misleading multi-timeframe analysis.

**Fix:** Add a check in `OnInit` that warns or rejects when any MTF timeframe <= current period.

---

### 9. Trend evaluation inconsistency between panel and signals (LOW)

**Location:** Lines 643 vs 835

- `GetTrendDirectionAtTime` (historical signals): reads `iClose(_Symbol, tf, barShift)` -- may include forming bar
- `GetCurrentTrend` (panel display): reads `iClose(_Symbol, tf, 1)` -- always last completed bar

**Impact:** Panel may show a different trend state than what recent signals were evaluated against.

---

### 10. No input validation in OnInit (LOW)

**Location:** Lines 123-200

No validation for any inputs:
- `Lookback` could be 0 or negative
- `MinTFAlignment` could be 0 or >3
- `TradingStartHour >= TradingEndHour` (no overnight session support)
- `ATR_Period`, `TrendEMA_Period` could be 0 or negative
- `MinSignalScore` could exceed 100
- `RiskRewardRatio` could be 0 or negative

---

### 11. Duplicate file in repository (LOW)

`10X_2_0_Indicator_Enhanced (1).mq5` is byte-for-byte identical to `10X_2_0_Indicator_Enhanced.mq5`. One should be removed.

---

### 12. Object name collision risk on same-bar signals (VERY LOW)

**Location:** Lines 428, 465

Entry zone and label object names use `IntegerToString(signalTime)` without signal type. Currently safe because a candle cannot be both bullish and bearish, but this is a fragile assumption if signal logic is ever modified.

---

## Priority Recommendations

1. **Fix #1 first** (counter accumulation) -- this is actively producing wrong data in the stats panel
2. **Fix #3** (pip value) -- directly affects SL/TP zone accuracy on 4-digit brokers
3. **Fix #2** (filter label cleanup) and **#5** (expiry naming) -- quick fixes that improve correctness and clarity
4. Address remaining items based on trading strategy priorities
