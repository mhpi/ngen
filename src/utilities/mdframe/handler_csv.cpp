#include <fstream>

#include <algorithm>

#include "mdframe/mdframe.hpp"

#include <boost/core/span.hpp>

namespace ngen {

/**
 * @brief 
 * 
 * @param shape 
 * @param index 
 * @param dimension 
 * @param output 
 */
void cartesian_indices_recurse(
    boost::span<const std::size_t>         shape,
    std::size_t                            current_dimension_index,
    std::vector<std::size_t>&              index_buffer,
    std::vector<std::vector<std::size_t>>& output
)
{
    if (current_dimension_index == shape.size()) {
        output.push_back(index_buffer);
        return;
    }

    for (std::size_t i = 0; i < shape[current_dimension_index]; i++) {
        index_buffer[current_dimension_index] = i;
        cartesian_indices_recurse(shape, current_dimension_index + 1, index_buffer, output);
    }
}

void cartesian_indices(const boost::span<const std::size_t> shape, std::vector<std::vector<std::size_t>>& output)
{
    std::vector<std::size_t> index_buffer(shape.size());
    cartesian_indices_recurse(shape, 0, index_buffer, output);
}

void mdframe::to_csv(const std::string& path, bool header) const
{
    std::ofstream output(path);
    if (!output)
        throw std::runtime_error("failed to open file " + path);
    
    std::string header_line = "";

    std::vector<variable> variable_subset;
    variable_subset.reserve(this->m_variables.size());

    // 1. Collect variables
    size_type max_rank = 0;
    for (const auto& pair : this->m_variables) {
        variable_subset.push_back(pair.second);
        size_type rank = pair.second.rank();
        if (rank > max_rank)
            max_rank = rank;
    }

    if (variable_subset.empty()) {
        throw std::runtime_error("cannot output CSV with no output variables");
    }

    // 2. Sort variables alphabetically by name for deterministic column order
    std::sort(variable_subset.begin(), variable_subset.end(), 
        [](const variable& a, const variable& b) {
            return a.name() < b.name();
        }
    );

    // 3. Generate Header
    for (const auto& var : variable_subset) {
        if (header)
            header_line += var.name() + ",";
    }

    // 4. Collect and Sort Dimensions alphabetically for deterministic row order
    std::vector<dimension> sorted_dimensions(this->m_dimensions.begin(), this->m_dimensions.end());
    std::sort(sorted_dimensions.begin(), sorted_dimensions.end(),
        [](const dimension& a, const dimension& b) {
            return a.name() < b.name();
        }
    );

    // 5. Calculate rows and shape based on sorted dimensions
    size_type rows = 1;
    std::vector<size_type> shape;
    shape.reserve(sorted_dimensions.size());
    for (const auto& dim : sorted_dimensions) {
        rows *= dim.size(); // Note: Original code used += which might be wrong for cartesian product size, usually it is *=.
                            // However, strictly following previous logic: rows is used for reserve.
                            // The shape logic is what matters for cartesian_indices.
        shape.push_back(dim.size());
    }
    // Correction: `cartesian_indices` generates product of sizes. If rows was for reserve, *= is closer to count.
    // Original code: rows += dim.size(); (This seems like an under-reservation but doesn't affect logic).

    if (header && header_line != "") {
        header_line.pop_back();
        output << header_line << std::endl;
    }

    // 6. Create index map using sorted dimensions
    std::unordered_map<std::string, std::vector<size_type>> vd_index;
    for (const auto& var : variable_subset) {
        vd_index[var.name()] = std::vector<size_type>{};
        std::vector<size_type>& variable_index = vd_index[var.name()];

        variable_index.reserve(var.rank());
        for (const auto& dim_name : var.dimensions()) {
            // Find the index of this dimension within our SORTED dimensions vector
            auto it = std::find_if(sorted_dimensions.begin(), sorted_dimensions.end(),
                [&dim_name](const dimension& d) { return d.name() == dim_name; });
            
            variable_index.push_back(std::distance(sorted_dimensions.begin(), it));
        }
    }

    detail::visitors::to_string_visitor visitor{};
    std::string output_line = "";
    std::vector<std::vector<size_type>> indices;
    indices.reserve(rows);

    ngen::cartesian_indices(shape, indices);
    
    std::vector<size_type> index_buffer(max_rank);
    for (const auto& index : indices) {
        for (auto var : variable_subset) {
            boost::span<size_type> index_view{ index_buffer.data(), var.rank() };
            boost::span<size_type> vd_view{vd_index[var.name()]};
            for (size_type i = 0; i < var.rank(); i++)
                index_view[i] = index.at(vd_view[i]);

            decltype(auto) value = var.at(index_view);
            output_line += value.apply_visitor(visitor) + ",";
        }

        output_line.pop_back();
        output << output_line << std::endl;
        output_line.clear();
    }
}

} // namespace ngen

