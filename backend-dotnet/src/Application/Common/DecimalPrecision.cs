namespace PurchaseAssistant.Application.Common;

public static class DecimalPrecision
{
    public static decimal Qty(decimal value) => Math.Round(value, 3);
    public static decimal Rate(decimal value) => Math.Round(value, 2);
    public static decimal Money(decimal value) => Math.Round(value, 2);
    public static decimal Weight(decimal value) => Math.Round(value, 4);
    public static decimal Percent(decimal value) => Math.Round(value, 2);
    public static decimal Total(decimal value) => Math.Round(value, 2);
}
