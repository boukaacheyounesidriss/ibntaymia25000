import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { Badge } from "@/components/ui/badge";
import { HELP_GUIDES } from "@/lib/help-content";

export function HelpGuides() {
  return (
    <Accordion type="single" collapsible className="w-full">
      {HELP_GUIDES.map((g, i) => (
        <AccordionItem key={g.q} value={String(i)}>
          <AccordionTrigger className="text-start text-base">
            <span className="flex flex-wrap items-center gap-2">
              {g.q}
              {g.roles && <Badge variant="outline">{g.roles}</Badge>}
            </span>
          </AccordionTrigger>
          <AccordionContent>
            <ol className="list-decimal space-y-2 pe-5 text-sm leading-relaxed">
              {g.steps.map((s) => <li key={s}>{s}</li>)}
            </ol>
          </AccordionContent>
        </AccordionItem>
      ))}
    </Accordion>
  );
}
