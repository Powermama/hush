// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The post's metadata in a side sheet, as Ghost's post settings: the fields of
// the article contract with their limits shown as you type.
import { blogAuthorIds, blogAuthors } from "@hush/article/authors";
import { blogArticleTypes, blogClusterIds, blogClusters, blogLanguages } from "@hush/article/taxonomy";
import { useState, type ReactNode } from "react";
import type { CreateDraftBody } from "@/api/cms.generated";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";

/** Every field of a post; the API also takes a draft with fields left out. */
export type PostDraft = Required<CreateDraftBody>;

function Field({ id, label, hint, children }: { id: string; label: string; hint?: ReactNode; children: ReactNode }) {
  return (
    <div className="grid gap-1.5">
      <Label htmlFor={id} className="text-[13px] font-semibold">{label}</Label>
      {children}
      {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
    </div>
  );
}

/** "52 / 50–60" in green inside the range, red outside it, as Ghost counts characters. */
function Count({ value, min, max }: { value: string; min: number; max: number }) {
  const ok = value.length >= min && value.length <= max;
  return <span className={cn("tabular-nums", ok ? "text-[var(--state-success)]" : "text-destructive")}>{value.length} / {min}–{max} characters</span>;
}

export function PostSettings({ draft, onChange, published }: {
  draft: PostDraft; onChange: (patch: Partial<PostDraft>) => void; published: boolean;
}) {
  const lang = draft.lang;
  // The typed text, so a trailing comma survives until the next keyword.
  const [keywordsText, setKeywordsText] = useState(draft.secondaryKeywords.join(", "));
  return (
    <div className="grid gap-5">
      <Field id="post-title" label="SEO title" hint={<Count value={draft.title} min={50} max={60} />}>
        <Input id="post-title" value={draft.title} onChange={(event) => onChange({ title: event.target.value })} />
      </Field>
      <Field id="post-description" label="Meta description" hint={<Count value={draft.description} min={140} max={160} />}>
        <Textarea id="post-description" rows={4} value={draft.description} onChange={(event) => onChange({ description: event.target.value })} />
      </Field>
      <div className="grid grid-cols-[1fr_2fr] gap-3">
        <Field id="post-lang" label="Language" hint={published ? "Unpublish to change." : undefined}>
          <Select value={lang} disabled={published} onValueChange={(value) => onChange({ lang: value as PostDraft["lang"] })}>
            <SelectTrigger id="post-lang" className="w-full"><SelectValue /></SelectTrigger>
            <SelectContent>{blogLanguages.map((code) => <SelectItem key={code} value={code}>{code === "en" ? "English" : "Deutsch"}</SelectItem>)}</SelectContent>
          </Select>
        </Field>
        <Field id="post-slug" label="URL" hint={`behu.sh/${lang === "de" ? "de/" : ""}blog/${draft.slug || "…"}`}>
          <Input id="post-slug" value={draft.slug} onChange={(event) => onChange({ slug: event.target.value.toLowerCase() })} />
        </Field>
      </div>
      <Field id="post-keyword" label="Main keyword" hint="One keyword per article and language.">
        <Input id="post-keyword" value={draft.keyword} onChange={(event) => onChange({ keyword: event.target.value })} />
      </Field>
      <Field id="post-secondary" label="Secondary keywords" hint="Comma-separated, up to 8.">
        <Input
          id="post-secondary"
          value={keywordsText}
          onChange={(event) => {
            setKeywordsText(event.target.value);
            onChange({ secondaryKeywords: event.target.value.split(",").map((keyword) => keyword.trim()).filter(Boolean) });
          }}
        />
      </Field>
      <div className="grid grid-cols-2 gap-3">
        <Field id="post-type" label="Type">
          <Select value={draft.type} onValueChange={(value) => onChange({ type: value as PostDraft["type"] })}>
            <SelectTrigger id="post-type" className="w-full"><SelectValue /></SelectTrigger>
            <SelectContent>{blogArticleTypes.map((type) => <SelectItem key={type} value={type}>{type}</SelectItem>)}</SelectContent>
          </Select>
        </Field>
        <Field id="post-cluster" label="Topic">
          <Select value={draft.cluster} onValueChange={(value) => onChange({ cluster: value as PostDraft["cluster"] })}>
            <SelectTrigger id="post-cluster" className="w-full"><SelectValue /></SelectTrigger>
            <SelectContent>{blogClusterIds.map((id) => <SelectItem key={id} value={id}>{blogClusters[id][lang]}</SelectItem>)}</SelectContent>
          </Select>
        </Field>
      </div>
      <Field id="post-author" label="Author">
        <Select value={draft.author} onValueChange={(value) => onChange({ author: value as PostDraft["author"] })}>
          <SelectTrigger id="post-author" className="w-full"><SelectValue /></SelectTrigger>
          <SelectContent>{blogAuthorIds.map((id) => <SelectItem key={id} value={id}>{blogAuthors[id].name}</SelectItem>)}</SelectContent>
        </Select>
      </Field>
      <Field id="post-image-alt" label="Cover alt text" hint={<Count value={draft.imageAlt} min={10} max={160} />}>
        <Textarea id="post-image-alt" rows={2} value={draft.imageAlt} onChange={(event) => onChange({ imageAlt: event.target.value })} />
      </Field>
    </div>
  );
}
