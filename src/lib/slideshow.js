export const SLIDE_SECONDS = 3;
export const MAX_SLIDES = 20;
export function photoUrls(media) {
  return media.photo_urls?.length ? media.photo_urls : [media.media_url || media.url].filter(Boolean);
}
export function photoDuration(count) {
  return count > 1 ? count * SLIDE_SECONDS : 7;
}
export function slideAt(time, count) {
  return Math.min(Math.max(0, count - 1), Math.floor(Math.max(0, time) / SLIDE_SECONDS));
}
