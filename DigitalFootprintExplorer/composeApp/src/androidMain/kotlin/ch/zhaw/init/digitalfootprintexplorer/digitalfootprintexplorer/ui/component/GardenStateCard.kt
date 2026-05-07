package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.component

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.R
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.GardenState

@Composable
fun GardenStateCard(state: GardenState?) {
    val imageRes = when (state) {
        GardenState.FLOURISHING -> R.drawable.garden_state_1_flourishing
        GardenState.GROWING -> R.drawable.garden_state_2_growing
        GardenState.STABLE -> R.drawable.garden_state_3_stable
        GardenState.WILTING -> R.drawable.garden_state_4_wilting
        GardenState.WITHERED -> R.drawable.garden_state_5_withered
        null -> R.drawable.garden_state_3_stable
    }

    val statusText = when (state) {
        GardenState.FLOURISHING -> stringResource(R.string.garden_state_flourishing)
        GardenState.GROWING -> stringResource(R.string.garden_state_growing)
        GardenState.STABLE -> stringResource(R.string.garden_state_stable)
        GardenState.WILTING -> stringResource(R.string.garden_state_wilting)
        GardenState.WITHERED -> stringResource(R.string.garden_state_withered)
        null -> stringResource(R.string.garden_state_unknown)
    }

    Card(
        modifier = Modifier
            .fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer
        ),
        shape = MaterialTheme.shapes.medium
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = Modifier
                    .size(200.dp)
                    .padding(bottom = 20.dp),
                contentAlignment = Alignment.Center
            ) {
                Image(
                    painter = painterResource(imageRes),
                    contentDescription = statusText,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Fit,
                    alpha = if (state == null) 0.3f else 1.0f
                )
            }

            Text(
                text = statusText,
                style = MaterialTheme.typography.headlineSmall,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onBackground
            )

            if (state != null) {
                Text(
                    text = stringResource(R.string.your_digital_garden),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.outline,
                    modifier = Modifier.padding(top = 4.dp)
                )
            }
        }
    }
}