from app.db.database import db

def clear_all_data():
    collections = [
        "teachers",
        "classrooms",
        "students",
        "student_photos",
        "lecture_dates",
        "attendance_records",
        "counters"
    ]
    
    print("[CLEAR] Clearing all document data from MongoDB Atlas...")
    for col in collections:
        res = db[col].delete_many({})
        print(f"   Deleted {res.deleted_count} documents from '{col}'")
    
    print("\n[OK] All data wiped cleanly! Sequence IDs reset to 1. Schema intact.")

if __name__ == "__main__":
    clear_all_data()
