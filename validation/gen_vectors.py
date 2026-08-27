import torch

torch.manual_seed(42)  # reproducible

ROWS, COLS = 8, 8

# Generate uint8-range weights and activations (0-255), matching DATA_W=8
weights = torch.randint(0, 256, (ROWS, COLS), dtype=torch.int32)
activations = torch.randint(0, 256, (ROWS,), dtype=torch.int32)

# Reference computation: matches psum_out = psum_in + (weight * act_in)
# accumulated down each column -> out[col] = sum over rows of weight[row][col] * act[row]
expected = torch.zeros(COLS, dtype=torch.int64)
for col in range(COLS):
    for row in range(ROWS):
        expected[col] += weights[row][col].item() * activations[row].item()

print("Weights (row-major, 8x8):")
print(weights)
print("\nActivations (8,):")
print(activations)
print("\nExpected psum_out (per column):")
print(expected)

# Write weight matrix as hex, one value per line, row-major
with open("weights.hex", "w") as f:
    for row in range(ROWS):
        for col in range(COLS):
            f.write(f"{weights[row][col].item():02x}\n")

# Write activations as hex, one per line
with open("activations.hex", "w") as f:
    for row in range(ROWS):
        f.write(f"{activations[row].item():02x}\n")

# Write expected outputs as hex, one per line (32-bit, matches ACC_W)
with open("expected.hex", "w") as f:
    for col in range(COLS):
        f.write(f"{expected[col].item():08x}\n")

print("\nWrote weights.hex, activations.hex, expected.hex")
