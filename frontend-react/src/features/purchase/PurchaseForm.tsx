"use client";

import { TradePurchaseOut, TradePurchaseUpdateIn } from "@/types/trade-purchase";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { purchaseUpdateSchema } from "@/schemas/trade-purchase";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from "@/components/ui/form";


type PurchaseFormProps = {
  initialData: TradePurchaseOut;
  onSubmit: (data: TradePurchaseUpdateIn) => void;
  isSubmitting: boolean;
  isReadOnly: boolean;
};

export function PurchaseForm({ initialData, onSubmit, isSubmitting, isReadOnly }: PurchaseFormProps) {
  const form = useForm<TradePurchaseUpdateIn>({
    resolver: zodResolver(purchaseUpdateSchema),
    defaultValues: {
      ...initialData,
      lines: initialData.lines || [],
    },
  });

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
        {/* Example: Supplier Field */}
        <FormField
          control={form.control}
          name="supplierId"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Supplier</FormLabel>
              <FormControl>
                <Input {...field} disabled={isReadOnly} />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        {/* Add more fields and line items here */}

        <Button type="submit" disabled={isSubmitting || isReadOnly}>
          {isSubmitting ? "Saving..." : "Save Changes"}
        </Button>
      </form>
    </Form>
  );
}