import React from "react";
import CommentSection from "@/components/gallery/CommentSection";

// Guestbook on a profile: comments stored with post_id "profile_<email>".
export default function ProfileMessageBoard({ profileUser }) {
  return (
    <div className="card p-5">
      <CommentSection entity="CommunityComment" field="post_id" targetId={`profile_${profileUser.email}`} ownerEmail={profileUser.email} link={`/Profile?email=${encodeURIComponent(profileUser.email)}`} />
    </div>
  );
}
