from typing import List


def compute_rating_summary(book_id: str, ratings: List[int]) -> dict:
    if not ratings:
        return {"book_id": book_id, "average_rating": None, "reviews_count": 0}
    average = round(sum(ratings) / len(ratings), 2)
    return {"book_id": book_id, "average_rating": average, "reviews_count": len(ratings)}
