// Adapted from Ghost Admin (TryGhost/Ghost apps/admin/src/shared/analytics/post-share-modal.tsx
// and apps/admin/src/posts/list/components/post-celebration-modal.tsx, c2617d08),
// MIT License, Copyright (c) 2013-2026 Ghost Foundation (see packages/theme/LICENSE.ghost).
// Changes for hush (2026-11-15, Clemens Kressmann, AGPL-3.0-only): no email-only
// or gift variants, the hush mark and name in place of the site icon and title,
// and the post read from the CMS.
//
// The post-publish celebration on the posts list: the headline, the post as a
// card linking to it on behu.sh, and the ways to share it.
import { blogAuthors, type BlogAuthorId } from "@hush/article/authors";
import type { Post } from "@/api/cms.generated";
import { HushLogo } from "@/components/hush-logo";
import { celebrationCopy } from "@/components/publish-celebration";
import ShareModal, { type ShareModalSocialLink } from "@/components/ui/share-modal";
import { articleUrl } from "@/lib/article-url";

export function PostCelebrationModal({ post, wasPublished, postCount, onClose }: {
  post: Post;
  wasPublished: boolean;
  /** Published posts, this one included; absent until the count has loaded. */
  postCount?: number;
  onClose: () => void;
}) {
  const copy = celebrationCopy({ wasPublished, postCount });
  const title = post.rendition?.heading ?? post.title;
  const url = articleUrl(post.lang, post.slug);
  const author = blogAuthors[post.author as BlogAuthorId]?.name ?? post.author;
  const encodedTitle = encodeURIComponent(title);
  const encodedUrl = encodeURIComponent(url);
  const encodedUrlTitle = encodeURIComponent(`${title} ${url}`);
  const socialLinks: ShareModalSocialLink[] = [
    { href: `https://twitter.com/intent/tweet?text=${encodedTitle}%0A${encodedUrl}`, label: "Share on X", service: "x" },
    { href: `https://threads.net/intent/post?text=${encodedUrlTitle}`, label: "Share on Threads", service: "threads" },
    { href: `https://www.facebook.com/sharer/sharer.php?u=${encodedUrl}`, label: "Share on Facebook", service: "facebook" },
    { href: `https://www.linkedin.com/shareArticle?mini=true&title=${encodedTitle}&url=${encodedUrl}`, label: "Share on LinkedIn", service: "linkedin" },
    { href: `https://bsky.app/intent/compose?text=${encodedUrlTitle}`, label: "Share on Bluesky", service: "bluesky" },
  ];

  return (
    <ShareModal.Root open onOpenChange={(open) => { if (!open) onClose(); }}>
      <ShareModal.Content
        aria-describedby={undefined}
        // The dialog itself takes the focus as it opens, so the close button shows no focus ring before anyone uses the keyboard.
        onOpenAutoFocus={(event) => { event.preventDefault(); (event.currentTarget as HTMLElement).focus(); }}
        className="outline-none"
      >
        <div className="sticky top-0 ml-auto size-0">
          <ShareModal.CloseButton className="absolute -top-5 -right-5" onClick={onClose} />
        </div>
        {/* On a phone the headline starts left and stops short of the close button, which would cover it centred. */}
        <ShareModal.Header className="relative -mt-5 pr-8 text-left sm:pr-0">
          <ShareModal.Title className="text-3xl leading-[1.15em] font-bold">
            {copy.primary && <span className="text-state-success">{copy.primary}</span>}
            {copy.primary && copy.secondary && <br />}
            {copy.secondary && <span>{copy.secondary}</span>}
          </ShareModal.Title>
        </ShareModal.Header>
        <ShareModal.Preview href={url}>
          <div className="p-6 pt-5">
            <h3 className="scroll-m-20 text-lg font-semibold tracking-tight text-text-primary">{title}</h3>
            {post.description && <p className="line-clamp-2">{post.description}</p>}
            <div className="mt-2 flex items-start gap-2">
              <HushLogo withName={false} className="mt-0.5 [&_svg]:size-4" />
              <div className="flex gap-1">
                <strong>hush</strong>
                <span>&bull;</span>
                <span>{author}</span>
              </div>
            </div>
          </div>
        </ShareModal.Preview>
        <ShareModal.Footer>
          <ShareModal.SocialLinks links={socialLinks} />
          <ShareModal.CopyButton className="ml-0! grow cursor-pointer" copyURL={url} icon="link" />
        </ShareModal.Footer>
      </ShareModal.Content>
    </ShareModal.Root>
  );
}
