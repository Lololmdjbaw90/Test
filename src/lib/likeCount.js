// Everyone's likes on a thing: like_count when it has one (the Like table,
// see src/lib/likes.js), otherwise its whole likes list.
export const likeCount = (record) => Math.max(0, typeof record?.like_count === "number" ? record.like_count : (record?.likes || []).length);
