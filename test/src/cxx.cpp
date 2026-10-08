/*
 * Minimal C++ code that uses the standard library and virtual functions.
 */

#include <numeric>
#include <vector>

namespace {

class Base {
public:
    virtual ~Base() = default;
    virtual int value() const = 0;
};

class One : public Base {
public:
    int value() const override { return 1; }
};

} /* namespace */

extern "C" int cxx_sum(int n)
{
    std::vector<int> values;
    One one;
    const Base &base = one;

    for (int i = 0; i < n; i++) {
        values.push_back(base.value());
    }

    return std::accumulate(values.begin(), values.end(), 0);
}
