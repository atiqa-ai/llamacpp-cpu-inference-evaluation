import json, sys

PROMPTS = {
    "math1": "If a train travels 240 km in 3 hours, what is its average speed in km/h? Show your work.",
    "math2": "A store sells apples at $0.40 each and pears at $0.25 each. If someone buys 5 apples and 8 pears, what is the total cost in dollars?",
    "math3": "What is the next number in the sequence: 2, 6, 12, 20, 30, ? Explain your reasoning.",
    "math4": "Alice is taller than Bob, and Charlie is shorter than Bob. Who is the tallest and who is the shortest?",
    "math5": "Solve for x: 3(x - 4) + 5 = 2x + 7. Provide a step-by-step solution.",
    "code1": "Write a Python function that returns the sum of all even numbers from 1 to n (inclusive).",
    "code2": "Write a Python function is_palindrome(s) that checks whether a given string reads the same forwards and backwards, ignoring case and spaces.",
    "code3": "Using JavaScript, write a function that takes an array of numbers and returns a new array with only the numbers greater than 10.",
    "inst1": "Rewrite the following sentence in formal academic English: 'the experiment was pretty cool and the results were kinda weird but still good.' Do not add extra commentary.",
    "inst2": "List exactly three benefits of regular exercise, in bullet points. Do not write anything else.",
    "inst3": "Translate this to French and keep it a single sentence: 'The quick brown fox jumps over the lazy dog.'",
}

if __name__ == "__main__":
    for k, v in PROMPTS.items():
        print(f"{k}\t{v}")