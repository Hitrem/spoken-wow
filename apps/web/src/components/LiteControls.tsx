/**
 * A button and a checkbox for controls repeated on every row of a long table.
 *
 * ui/button and ui/checkbox look the same but cost far more per copy: the button carries about
 * 940 characters of classes, and the checkbox is a Radix component with its own state, context
 * and a hidden input. A hundred rows of those were most of /contributions's HTML and much of
 * the work the browser did on load. These are plain elements with short class strings.
 */
import type { ComponentProps } from "react";

import { cn } from "@/lib/utils";

const BASE =
  "inline-flex h-7 shrink-0 items-center rounded-md px-2.5 text-[0.8rem] font-medium whitespace-nowrap " +
  "hover:bg-muted focus-visible:ring-ring/50 outline-none focus-visible:ring-3 disabled:pointer-events-none disabled:opacity-50";

const VARIANTS = {
  outline: "border-border bg-background border",
  ghost: "",
} as const;

export function LiteButton({
  variant = "outline",
  className,
  type = "button",
  ...props
}: ComponentProps<"button"> & { variant?: keyof typeof VARIANTS }) {
  return <button type={type} className={cn(BASE, VARIANTS[variant], className)} {...props} />;
}

export function LiteCheckbox({ className, ...props }: Omit<ComponentProps<"input">, "type">) {
  return (
    <input
      type="checkbox"
      className={cn("accent-primary dark:scheme-dark size-4 cursor-pointer disabled:cursor-not-allowed disabled:opacity-50", className)}
      {...props}
    />
  );
}
